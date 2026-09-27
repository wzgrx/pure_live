import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/huya/huya_parse.dart';
import 'package:live_core/src/sites/huya/huya_sign.dart';
import 'package:live_core/src/sites/huya/huya_tars.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';
import 'package:live_net/live_net.dart';

const _site = 'huya';
const _web = 'https://www.huya.com';

/// §2.2 / §4.1 the mobile Chrome UA of the API requests
/// (huya_request_params.dart kUserAgent).
const _mobileUserAgent =
    'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/90.0.4430.91 Mobile Safari/537.36 Edg/117.0.0.0';

/// A desktop browser UA for room pages (alias lookup).
const _desktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/140.0.0.0 Safari/537.36';

/// §6.5 the Huya client identity shipped with the adapter: the native tId
/// UA, the web tId UA and the token application id.
const _nativeTarsUserAgent = 'pc_exe&7060000&official';
const _webTarsUserAgent = 'webh5&0.1.0&websocket';

/// §3 search page size (1–50).
const _searchRows = 20;

/// §6.2 a WUP exchange as a whole.
const _wupTimeout = Duration(seconds: 8);

/// Path segments on huya.com that are pages, not rooms (§1).
const _reserved = {
  'g',
  'l',
  'e',
  'search',
  'video',
  'videos',
  'directory',
  'game',
  'games',
  'category',
  'user',
  'users',
  'index',
  'topic',
  'download',
  'downloads',
  'myfollow',
  'login',
  'signup',
  'settings',
};

/// A WUP `getCdnTokenInfoEx` answer and when it arrived.
typedef _Token = ({String token, int expireTime, DateTime receivedAt});

/// A signed query for one line: the token window when it came from WUP, and
/// whether it is the native FLV credential.
typedef _Signed = ({String antiCode, HuyaTokenWindow? window, bool native});

/// The outcome of opening one line.
typedef _Opened = ({StreamLine? line, bool native, SiteError? error, bool expired});

/// The Huya adapter (spec/sites/huya.md): parsing from [HuyaParse], requests
/// over [LiveHttp], AntiCode signing with [HuyaSign] and WUP token requests
/// with the Tars codec in huya_tars.dart.
final class HuyaSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter. [_cookies] holds the user's account cookie, if any.
  /// [now], [random] and [signClock] are injectable for tests; the default
  /// sign clock is shared by the whole process (§6.4 step 4).
  new(this.http, {this._cookies, DateTime Function()? now, Random? random, HuyaSignClock? signClock})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure(),
      _signClock = signClock ?? HuyaSignClock.process;

  /// Transport.
  final LiveHttp http;
  final CookieVault? _cookies;
  final DateTime Function() _now;
  final Random _random;
  final HuyaSignClock _signClock;

  /// §8 this instance's GUID for the web tId.
  late final String _guid = HuyaSign.guid(_random);

  /// §8 the local temporary UID used while anonymous login fails; never
  /// cached as the official identity (REG-HUYA-017).
  late final int _fallbackUid = HuyaSign.fallbackViewerUid(_random);

  int? _anonymousUid;
  Future<int?>? _anonymousLogin;
  final Map<String, Future<_Token>> _nativeTokens = {};
  final Map<String, Future<_Token>> _webTokens = {};
  int _nativeFallbacks = 0;
  int _degradedViewers = 0;

  @override
  String get id => _site;

  @override
  String get name => '虎牙';

  /// §9 diagnostics: FLV lines that fell back from the native WUP credential
  /// to the web path. Not an error.
  int get nativeFallbacks => _nativeFallbacks;

  /// §9 diagnostics: stream requests signed with the local temporary viewer
  /// UID because anonymous login failed. Not an error.
  int get degradedViewers => _degradedViewers;

  /// The user's cookie, without a `Cookie:` prefix or control characters.
  String? get _cookie {
    final raw = _cookies
        ?.cookieFor(_site)
        ?.replaceFirst(RegExp(r'^\s*Cookie:\s*', caseSensitive: false), '')
        .replaceAll(RegExp('[\x00-\x1f\x7f]'), '')
        .trim();
    return raw == null || raw.isEmpty ? null : raw;
  }

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

  // ---------------------------------------------------------------------------
  // Catalog

  /// §2.1 the four top-level categories, requested concurrently; any failure
  /// fails the whole tree.
  @override
  Future<List<Category>> categories() => Future.wait([for (final top in HuyaParse.topCategories) _category(top.id)]);

  Future<Category> _category(String id) async {
    final response = await _get(Uri.https('live.cdn.huya.com', '/liveconfig/game/bussLive', {'bussType': id}), const {
      'user-agent': _mobileUserAgent,
    });
    return HuyaParse.category(response.text, id: id, status: response.status);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) => _liveList(cursor, gameId: area.id);

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => _liveList(cursor);

  /// §2.2 `getLiveListByPage`; the cursor is the next page number. No cookie
  /// (§2.2: not needed until confirmed).
  Future<Page<RoomCard>> _liveList(PageCursor? cursor, {String? gameId}) async {
    final page = max(1, int.tryParse(cursor?.value ?? '') ?? 1);
    final response = await _get(
      Uri.https('www.huya.com', '/cache.php', {
        'm': 'LiveList',
        'do': 'getLiveListByPage',
        'tagAll': '0',
        'gameId': ?gameId,
        'page': '$page',
      }),
      {
        'user-agent': _mobileUserAgent,
        if (gameId == null) ...{'origin': _web, 'referer': '$_web/'},
      },
    );
    return HuyaParse.roomListPage(response.text, page: page, status: response.status);
  }

  // ---------------------------------------------------------------------------
  // Search

  /// §3 live rooms only; the cursor is the next `start`.
  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final query = keyword.trim();
    if (query.isEmpty) return const Page.empty();
    final start = max(0, int.tryParse(cursor?.value ?? '') ?? 0);
    final response = await _get(
      Uri.https('search.cdn.huya.com', '/', {
        'm': 'Search',
        'do': 'getSearchContent',
        'q': query,
        'uid': '0',
        'v': '4',
        'typ': '-5',
        'livestate': '0',
        'rows': '$_searchRows',
        'start': '$start',
      }),
      const {'user-agent': _mobileUserAgent},
    );
    return HuyaParse.searchPage(response.text, start: start, rows: _searchRows, status: response.status);
  }

  // ---------------------------------------------------------------------------
  // Room detail

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final response = await _profileRoom(ref.roomId);
    return HuyaParse.detail(response.text, status: response.status, roomId: ref.roomId);
  }

  /// §4.1 `profileRoom` past the ~30 s public cache: a millisecond `_` and
  /// no-cache headers (REG-HUYA-016). No cookie until one is shown to matter.
  Future<LiveResponse> _profileRoom(String roomId) => _get(
    Uri.https('mp.huya.com', '/cache.php', {
      'm': 'Live',
      'do': 'profileRoom',
      'roomid': roomId,
      'showSecret': '1',
      '_': '${_now().millisecondsSinceEpoch}',
    }),
    const {
      'accept': '*/*',
      'origin': _web,
      'referer': '$_web/',
      'sec-fetch-dest': 'empty',
      'sec-fetch-mode': 'cors',
      'sec-fetch-site': 'same-site',
      'user-agent': _mobileUserAgent,
      'cache-control': 'no-cache',
      'pragma': 'no-cache',
    },
  );

  // ---------------------------------------------------------------------------
  // Streams

  /// §6.1 every open re-requests `profileRoom` and signs every line in
  /// parallel. A line that cannot be signed is dropped alone (REG-HUYA-011).
  ///
  /// Lines come in the §5.3 fallback order, server order inside each group:
  /// native FLV, web FLV, HLS. When no line opens: an expired AntiCode
  /// re-requests `profileRoom` once and is ApiChanged if still expired; a
  /// structural cause is ApiChanged; only network failures are
  /// NetworkFailure; anything else is StreamUnavailable (§9).
  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final roomId = room.ref.roomId;
    for (var attempt = 0; ; attempt++) {
      final response = await _profileRoom(roomId);
      final data = HuyaParse.playData(response.text, status: response.status);
      final qualities = HuyaParse.qualities(data);
      final selected = HuyaParse.selectQuality(qualities, quality);
      final lines = HuyaParse.lines(data);
      // One viewer identity per open, resolved only when a web template needs it.
      Future<int>? viewer;
      Future<int> viewerUid() => viewer ??= _viewerUid();
      final results = await Future.wait([for (final line in lines) _open(line, selected, roomId, viewerUid)]);
      final opened = [
        for (final result in results)
          if (result.line != null) result,
      ];
      if (opened.isNotEmpty) {
        final ordered = [
          for (final result in opened)
            if (result.native) result.line!,
          for (final result in opened)
            if (!result.native && result.line!.format == StreamFormat.flv) result.line!,
          for (final result in opened)
            if (result.line!.format == StreamFormat.hls) result.line!,
        ];
        final seen = <String>{};
        return StreamSet(
          qualities: qualities,
          selected: selected,
          lines: [
            for (final line in ordered)
              if (seen.add(line.url.toString())) line,
          ],
        );
      }
      if (attempt == 0 && results.any((result) => result.expired)) continue;
      throw _failure(results);
    }
  }

  static SiteError _failure(List<_Opened> results) {
    if (results.any((result) => result.expired)) {
      return const ApiChanged(_site, 'AntiCode still expired after a fresh profileRoom');
    }
    final errors = results.map((result) => result.error).nonNulls.toList();
    final structural = errors.whereType<ApiChanged>().firstOrNull;
    if (structural != null) return structural;
    if (errors.isNotEmpty && errors.every((error) => error is NetworkFailure)) return errors.first;
    return StreamUnavailable(
      _site,
      'no line could be signed (${errors.map((error) => error.kind).toSet().join(', ')})',
    );
  }

  /// Signs one line and builds its media URL, headers and lease. Failures
  /// stay with the line; only cancellation escapes.
  Future<_Opened> _open(HuyaLine line, Quality quality, String roomId, Future<int> Function() viewer) async {
    var expired = false;
    void markExpired() => expired = true;
    try {
      final signed = line.format == StreamFormat.flv
          ? await _signFlv(line, viewer, markExpired)
          : await _signWeb(line.antiCode, line, viewer, markExpired);
      if (signed.antiCode.trim().isEmpty) {
        throw StreamUnavailable(_site, '${line.format.name} ${line.cdnType}: no token');
      }
      // An `fm` left over (an empty one is not a template) would be refused by the CDN.
      if (RegExp(r'(^|&)fm(=|&|$)').hasMatch(signed.antiCode)) throw const ApiChanged(_site, 'AntiCode: empty fm');
      final url = HuyaParse.mediaUrl(line, antiCode: signed.antiCode, quality: quality);
      final stream = HuyaParse.streamLine(
        line,
        url: url,
        requested: quality,
        roomId: roomId,
        builtAt: _now(),
        token: signed.window,
      );
      return (line: stream, native: signed.native, error: null, expired: false);
    } on HuyaSignFailure catch (failure) {
      if (failure.kind == HuyaSignFailureKind.expired) expired = true;
      return (line: null, native: false, error: ApiChanged(_site, 'AntiCode: ${failure.reason}'), expired: expired);
    } on SiteError catch (error) {
      return (line: null, native: false, error: error, expired: expired);
    }
  }

  /// §6.1 / §6.2 / §6.3 FLV: the native WUP credential first, whatever the
  /// room token looks like (REG-HUYA-003); then the web path.
  Future<_Signed> _signFlv(HuyaLine line, Future<int> Function() viewer, void Function() markExpired) async {
    try {
      return await _nativeFlv(line, viewer);
    } on HuyaSignFailure {
      _nativeFallbacks++;
    } on SiteError {
      _nativeFallbacks++;
    }
    try {
      return await _signWeb(line.antiCode, line, viewer, markExpired);
    } on HuyaSignFailure catch (failure) {
      if (failure.kind == HuyaSignFailureKind.expired) markExpired();
    }
    // §6.3 step 3: a fresh web token for this viewer and line.
    final uid = await viewer();
    final token = await _webToken(line, uid);
    final window = HuyaParse.tokenWindow(token.token, expireTime: token.expireTime, receivedAt: token.receivedAt);
    return (antiCode: await _signWith(token.token, line, () async => uid), window: window, native: false);
  }

  /// §6.2 the native signed FLV credential for [line]: `getCdnTokenInfoEx`
  /// with the `pc_exe` identity (no cookie, no viewer UID), signed with the
  /// line's streamer UID, or the viewer's when it has none. Throws a
  /// `SiteError` or [HuyaSignFailure] when it cannot be used.
  Future<_Signed> _nativeFlv(HuyaLine line, Future<int> Function() viewer) async {
    final token = await _nativeToken(line.streamName);
    final window = HuyaParse.tokenWindow(token.token, expireTime: token.expireTime, receivedAt: token.receivedAt);
    if (!_now().isBefore(window.invalidAt)) {
      throw const HuyaSignFailure(HuyaSignFailureKind.expired, 'native token arrived expired');
    }
    final uid = line.presenterUid;
    return (
      antiCode: await _signWith(token.token, line, uid == null ? viewer : () async => uid),
      window: window,
      native: true,
    );
  }

  /// §6.3 steps 1–2 and §6.1 HLS: a static token as is, a template signed as
  /// the viewer.
  Future<_Signed> _signWeb(
    String antiCode,
    HuyaLine line,
    Future<int> Function() viewer,
    void Function() markExpired,
  ) async {
    try {
      return (antiCode: await _signWith(antiCode.trim(), line, viewer), window: null, native: false);
    } on HuyaSignFailure catch (failure) {
      if (failure.kind == HuyaSignFailureKind.expired) markExpired();
      rethrow;
    }
  }

  /// Signs [antiCode] when it is a template; the UID is only resolved then.
  Future<String> _signWith(String antiCode, HuyaLine line, Future<int> Function() uid) async {
    if (!HuyaSign.hasTemplate(antiCode)) return antiCode;
    final signer = await uid();
    return HuyaSign.sign(
      antiCode,
      streamName: line.streamName,
      uid: signer,
      clock: _signClock,
      now: _now(),
      random: _random,
    );
  }

  /// §6.2 one native request per stream name at a time; every caller signs
  /// its own URL, nothing is cached.
  Future<_Token> _nativeToken(String streamName) => _nativeTokens[streamName] ??= _fetchToken(
    flvUrl: '',
    streamName: streamName,
    userId: const HuyaUserId(huyaUa: _nativeTarsUserAgent),
    headers: const {'origin': _web, 'referer': '$_web/', 'user-agent': HuyaParse.mediaUserAgent},
  ).whenComplete(() => _forget(_nativeTokens, streamName));

  /// §6.3 step 3 the web token for [line] as viewer [uid], with the user's
  /// cookie; only the same viewer, line and stream share a request.
  Future<_Token> _webToken(HuyaLine line, int uid) {
    final key = '$uid|${line.base}|${line.streamName}';
    final cookie = _cookie;
    return _webTokens[key] ??= _fetchToken(
      flvUrl: line.base.toString(),
      streamName: line.streamName,
      userId: HuyaUserId(uid: uid, guid: _guid, huyaUa: _webTarsUserAgent, cookie: cookie ?? ''),
      headers: {'origin': _web, 'referer': '$_web/', 'user-agent': _mobileUserAgent, 'cookie': ?cookie},
    ).whenComplete(() => _forget(_webTokens, key));
  }

  /// Drops a finished in-flight request. A block body on purpose: an arrow
  /// body returns the removed future at runtime, and `whenComplete` would wait
  /// for the very future it completes.
  static void _forget(Map<String, Object> inFlight, String key) {
    inFlight.remove(key);
  }

  /// `POST https://wup.huya.com` `liveui.getCdnTokenInfoEx` (§6.2). A
  /// non-zero return code is StreamUnavailable, undecodable bytes ApiChanged.
  Future<_Token> _fetchToken({
    required String flvUrl,
    required String streamName,
    required HuyaUserId userId,
    required Map<String, String> headers,
  }) async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('wup.huya.com', '/'),
        method: 'POST',
        headers: {...headers, 'content-type': 'application/x-wup'},
        body: HuyaCdnTokenCall.request(flvUrl: flvUrl, streamName: streamName, userId: userId),
        timeout: _wupTimeout,
      ),
    );
    if (response.status >= 500) throw NetworkFailure(_site, 'getCdnTokenInfoEx HTTP ${response.status}');
    if (response.status != 200) throw StreamUnavailable(_site, 'getCdnTokenInfoEx HTTP ${response.status}');
    final ({int code, String token, int expireTime}) result;
    try {
      result = HuyaCdnTokenCall.response(response.bytes);
    } on FormatException catch (error) {
      throw ApiChanged(_site, 'getCdnTokenInfoEx: ${error.message}');
    }
    if (result.code != 0) throw StreamUnavailable(_site, 'getCdnTokenInfoEx code ${result.code}');
    return (token: result.token.trim(), expireTime: result.expireTime, receivedAt: _now());
  }

  /// §8 the viewer UID for web signing: the cookie's `yyuid`, else the
  /// cached anonymous UID, else a (shared) anonymous login; a failed login
  /// signs with the local temporary UID and retries next time.
  Future<int> _viewerUid() async {
    final account = HuyaSign.viewerUidFromCookie(_cookie);
    if (account != null) return account;
    final cached = _anonymousUid;
    if (cached != null) return cached;
    final uid = await (_anonymousLogin ??= () async {
      try {
        return _anonymousUid = await _login();
      } finally {
        _anonymousLogin = null;
      }
    }());
    if (uid != null) return uid;
    _degradedViewers++;
    return _fallbackUid;
  }

  /// §8 `anonymousLogin`; null when it fails. Only cancellation escapes.
  Future<int?> _login() async {
    try {
      final response = await _send(
        LiveRequest(
          site: _site,
          url: Uri.https('udblgn.huya.com', '/web/anonymousLogin'),
          method: 'POST',
          headers: const {
            'content-type': 'application/json',
            'accept': '*/*',
            'origin': _web,
            'referer': '$_web/',
            'sec-fetch-dest': 'empty',
            'sec-fetch-mode': 'cors',
            'sec-fetch-site': 'same-site',
            'user-agent': _mobileUserAgent,
          },
          body: utf8.encode(
            jsonEncode({'appId': 5002, 'byPass': 3, 'context': '', 'version': '2.4', 'data': <String, Object?>{}}),
          ),
        ),
      );
      if (response.status != 200) return null;
      final decoded = jsonDecode(response.text);
      final data = decoded is Map ? decoded['data'] : null;
      final uid = data is Map ? jsonInt(data['uid']) : null;
      return uid != null && uid > 0 ? uid : null;
    } on NetworkFailure {
      return null;
    } on FormatException {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Links

  /// §1 numbers, room pages on huya.com and its subdomains (in share text
  /// too), and letter aliases, which `profileRoom` refuses (S06-alias): an
  /// alias is looked up on its room page.
  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (RegExp(r'^\d+$').hasMatch(text)) return _ref(text);
    final match =
        RegExp(r'https?://[^\s，。！？、]+').firstMatch(text) ??
        RegExp(r'(?:^|[^\w.-])((?:[\w-]+\.)*huya\.com(?![\w.-])(?:[/?#][^\s，。！？、]*)?)').firstMatch(text);
    if (match == null) return null;
    var link = match.group(match.groupCount)!;
    if (!link.startsWith(RegExp('https?://'))) link = 'https://$link';
    final url = Uri.tryParse(link);
    final host = url?.host.toLowerCase() ?? '';
    if (url == null || !(host == 'huya.com' || host.endsWith('.huya.com'))) return null;
    final segment = url.pathSegments.where((segment) => segment.isNotEmpty).firstOrNull;
    if (segment == null || _reserved.contains(segment.toLowerCase())) return null;
    if (RegExp(r'^\d+$').hasMatch(segment)) return _ref(segment);
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(segment)) return null;
    return await _alias(segment);
  }

  static RoomRef? _ref(String id) {
    try {
      return RoomRef(_site, id);
    } on FormatException {
      return null;
    }
  }

  /// The numeric room behind [alias]: the room page's `TT_ROOM_DATA`
  /// `profileRoom`. A page without one is NotFound.
  Future<RoomRef> _alias(String alias) async {
    final response = await _get(Uri.https('www.huya.com', '/$alias'), const {
      'user-agent': _desktopUserAgent,
      'accept': 'text/html,application/xhtml+xml',
    });
    if (response.status >= 500) throw NetworkFailure(_site, 'room page HTTP ${response.status}');
    if (response.status == 429) throw const RateLimited(_site, detail: 'room page HTTP 429');
    final id = response.status == 200 ? _roomIdFromPage(response.text) : null;
    final ref = id == null ? null : _ref(id);
    if (ref == null) throw NotFound(_site, 'alias $alias has no room');
    return ref;
  }

  /// The numeric `profileRoom` of a room page: `var TT_ROOM_DATA = {...}`,
  /// else the first `"profileRoom"` value in the page; null without one.
  static String? _roomIdFromPage(String html) {
    final data = RegExp(r'var\s+TT_ROOM_DATA\s*=\s*(\{.*?\})\s*;', dotAll: true).firstMatch(html);
    if (data != null) {
      try {
        final decoded = jsonDecode(data.group(1)!);
        final id = decoded is Map ? jsonString(decoded['profileRoom']) : null;
        if (id != null && RegExp(r'^\d+$').hasMatch(id) && id != '0') return id;
      } on FormatException {
        // Fall through to the loose match.
      }
    }
    final loose = RegExp(r'"profileRoom"\s*:\s*"?(\d+)"?').firstMatch(html)?.group(1);
    return loose == null || loose == '0' ? null : loose;
  }
}
