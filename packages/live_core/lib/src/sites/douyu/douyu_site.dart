import 'dart:async';
import 'dart:math';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/douyu/douyu_parse.dart';
import 'package:live_core/src/sites/douyu/douyu_session.dart';
import 'package:live_core/src/sites/douyu/douyu_sign.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'douyu';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// Path segments on douyu.com that are pages, not rooms (spec §1).
const _reserved = {'search', 'topic', 'directory', 'video', 'user', 'index', 'login', 'g_', 'member', 'cms'};

/// The Douyu adapter (spec/sites/douyu.md): parsing from [DouyuParse],
/// requests over [LiveHttp], signing with a cached descriptor.
final class DouyuSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter. [_cookies] holds the user's account cookie, if any;
  /// [now] and [random] are injectable for tests.
  new(this.http, {this._cookies, DateTime Function()? now, Random? random})
    : _now = now ?? DateTime.now,
      _processDid = List.generate(32, (_) => (random ?? Random.secure()).nextInt(16).toRadixString(16)).join();

  /// Transport.
  final LiveHttp http;
  final CookieVault? _cookies;
  final DateTime Function() _now;

  /// §6.6 per-process DID used when the account cookie has none.
  final String _processDid;

  ({String did, DouyuDescriptor descriptor, DateTime fetchedAt})? _descriptor;
  Future<DouyuDescriptor>? _descriptorFetch;

  @override
  String get id => _site;

  @override
  String get name => '斗鱼';

  Map<String, String> _accountCookie() {
    final raw = _cookies?.cookieFor(_site);
    if (raw == null) return <String, String>{};
    final fields = <String, String>{};
    for (final part in raw.replaceFirst(RegExp(r'^\s*Cookie:\s*', caseSensitive: false), '').split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      if (!RegExp(r'^[A-Za-z0-9_\-.]+$').hasMatch(name)) continue;
      fields[name] = part.substring(separator + 1).trim().replaceAll(RegExp('[\x00-\x1f]'), '');
    }
    return fields;
  }

  /// §6.6 one DID for the descriptor, the signed form and every cookie.
  String get did => _accountCookie()['dy_did'] ?? _processDid;

  /// §6.7 cookie: DID first, then the account fields without LTP0.
  String _cookieHeader() {
    final account = _accountCookie()..removeWhere((name, _) => name == 'dy_did' || name == 'acf_did' || name == 'LTP0');
    return [
      'dy_did=$did',
      'acf_did=$did',
      for (final entry in account.entries) '${entry.key}=${entry.value}',
    ].join('; ');
  }

  /// §6.7 API headers; also used for media requests.
  Map<String, String> _headers({String? rid}) => {
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'zh-CN,zh;q=0.9,en;q=0.7',
    'origin': 'https://www.douyu.com',
    'referer': rid == null ? 'https://www.douyu.com/' : 'https://www.douyu.com/$rid',
    'user-agent': _userAgent,
    'cookie': _cookieHeader(),
  };

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(String url, {String? rid, Map<String, String>? headers}) => _send(
    LiveRequest(
      site: _site,
      url: Uri.parse(url),
      headers: headers ?? _headers(rid: rid),
    ),
  );

  static void _requireSuccess(LiveResponse response, String what) {
    if (response.status >= 500) throw NetworkFailure(_site, '$what HTTP ${response.status}');
  }

  @override
  Future<List<Category>> categories() async {
    final response = await _get('https://m.douyu.com/api/cate/list', headers: const {'user-agent': _userAgent});
    _requireSuccess(response, 'cate/list');
    return DouyuParse.categories(response.text);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final response = await _get('https://www.douyu.com/gapi/rkc/directory/mixList/2_${area.id}/$page');
    _requireSuccess(response, 'mixList');
    return DouyuParse.roomListPage(response.text, page: page);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final response = await _get('https://www.douyu.com/japi/weblist/apinc/allpage/6/$page');
    _requireSuccess(response, 'allpage');
    return DouyuParse.roomListPage(response.text, page: page);
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final url = Uri.https('www.douyu.com', '/japi/search/api/searchShow', {
      'kw': keyword,
      'page': '$page',
      'pageSize': '20',
    });
    final response = await _send(
      LiveRequest(site: _site, url: url, headers: {..._headers(), 'referer': 'https://www.douyu.com/search/'}),
    );
    _requireSuccess(response, 'searchShow');
    return DouyuParse.searchPage(response.text, page: page);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final response = await _get('https://www.douyu.com/betard/${Uri.encodeComponent(ref.roomId)}', rid: ref.roomId);
    _requireSuccess(response, 'betard');
    return DouyuParse.detail(response.text, status: response.status);
  }

  /// §6.1 descriptor cache: reused for 5 minutes for the same DID while
  /// usable; concurrent callers share one request.
  Future<DouyuDescriptor> _descriptorFor(String did, {bool force = false}) {
    final cached = _descriptor;
    final now = _now();
    if (!force &&
        cached != null &&
        cached.did == did &&
        now.difference(cached.fetchedAt) < const Duration(minutes: 5) &&
        cached.descriptor.usableAt(now)) {
      return Future.value(cached.descriptor);
    }
    return _descriptorFetch ??= () async {
      try {
        final response = await _get('https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption?did=$did');
        _requireSuccess(response, 'getEncryption');
        final descriptor = DouyuDescriptor.parse(response.text);
        _descriptor = (did: did, descriptor: descriptor, fetchedAt: _now());
        return descriptor;
      } finally {
        _descriptorFetch = null;
      }
    }();
  }

  /// §6.3/§6.4 one play request for (rate, cdn); the second attempt forces a
  /// fresh descriptor.
  Future<Map<String, dynamic>> _play(String rid, {required String rate, required String cdn}) async {
    SiteError? last;
    for (var attempt = 0; attempt < 2; attempt++) {
      final currentDid = did;
      final descriptor = await _descriptorFor(currentDid, force: attempt > 0);
      final tt = _now().millisecondsSinceEpoch ~/ 1000;
      final response = await _send(
        LiveRequest.form(
          site: _site,
          url: Uri.parse('https://www.douyu.com/lapi/live/getH5PlayV1/$rid'),
          headers: _headers(rid: rid),
          fields: {
            'enc_data': descriptor.encData,
            'tt': '$tt',
            'did': currentDid,
            'auth': descriptor.auth(rid, tt),
            'cdn': cdn,
            'rate': rate,
            'hevc': '0',
            'fa': '0',
            'ive': '0',
            'ver': 'Douyu_new',
            'iar': '0',
          },
        ),
      );
      try {
        return DouyuParse.playData(response.text, status: response.status);
      } on StreamUnavailable {
        rethrow;
      } on SiteError catch (error) {
        last = error;
      }
    }
    throw last!;
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final rid = room.ref.roomId;
    final meta = await _play(rid, rate: '-1', cdn: '');
    final qualities = DouyuParse.qualities(meta);
    final cdns = DouyuParse.cdns(meta);
    final requested = quality ?? qualities.first;

    // §5.4 sign every CDN at the requested rate, then keep one cohort.
    final results = <({String cdn, Map<String, dynamic> data, DateTime issuedAt})>[];
    SiteError? lastError;
    for (final cdn in cdns) {
      final issuedAt = _now();
      try {
        results.add((cdn: cdn, data: await _play(rid, rate: requested.id, cdn: cdn), issuedAt: issuedAt));
      } on SiteError catch (error) {
        lastError = error;
      }
    }
    if (results.isEmpty) throw lastError ?? const StreamUnavailable(_site, 'no CDN answered');
    final confirmedRates = [for (final result in results) DouyuParse.confirmedRate(result.data)];
    final chosen = confirmedRates.contains(requested.id)
        ? requested.id
        : confirmedRates.firstWhere((rate) => rate != null, orElse: () => null);
    Quality? confirmed;
    if (chosen != null) {
      confirmed = qualities.where((q) => q.id == chosen).firstOrNull ?? Quality(id: chosen, label: chosen, rank: -1);
    }
    final headers = {for (final entry in _headers(rid: rid).entries) entry.key: entry.value}
      ..remove('accept')
      ..remove('accept-language');
    final lines = <StreamLine>[
      for (final (index, result) in results.indexed)
        if (confirmedRates[index] == chosen)
          if (DouyuParse.mediaUrl(result.data) case final url?)
            StreamLine(
              url: url,
              format: StreamFormat.flv,
              lineId: result.cdn,
              requested: requested,
              confirmed: confirmed,
              headers: headers,
              codec: 'avc',
              lease: DouyuParse.lease(url, result.issuedAt),
            ),
    ];
    if (lines.isEmpty) throw const ApiChanged(_site, 'getH5PlayV1: no playable URL');
    return StreamSet(qualities: qualities, selected: requested, lines: lines);
  }

  /// §8.2 renews the login [cookie] at the passport with [ltp0] and [did]:
  /// the request's cookie is only `dy_did` and `LTP0` (§8.3) and only the
  /// response's `Set-Cookie` is read. Returns the merged cookie, or null when
  /// nothing was renewed (no `Set-Cookie`, or no session token after the
  /// merge); the caller then keeps the old cookie. Network errors throw.
  Future<String?> renewSession({required String cookie, required String ltp0, required String did}) async {
    final stamp = '${_now().millisecondsSinceEpoch}';
    final headers = _headers()..['cookie'] = '${DouyuSession.deviceIdName}=$did;${DouyuSession.longTermName}=$ltp0';
    final response = await _get(
      Uri.https('passport.douyu.com', '/lapi/passport/iframe/safeAuth', {
        'client_id': '1',
        't': stamp,
        '_': stamp,
        'callback': 'axiosJsonpCallback',
      }).toString(),
      headers: headers,
    );
    _requireSuccess(response, 'safeAuth');
    final lines = response.headers['set-cookie'] ?? const <String>[];
    if (lines.isEmpty) return null;
    final renewed = DouyuSession.merge(cookie, lines);
    return DouyuSession.sessionToken(renewed) == null ? null : renewed;
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (RegExp(r'^\d+$').hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null || !(url.host == 'douyu.com' || url.host.endsWith('.douyu.com'))) return null;
    final segment = url.pathSegments.where((s) => s.isNotEmpty).firstOrNull;
    if (segment == null || _reserved.contains(segment)) return null;
    if (RegExp(r'^\d+$').hasMatch(segment)) return RoomRef(_site, segment);
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(segment)) return null;
    // An alias page redirects to /<rid> (the betard API refuses aliases).
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('www.douyu.com', '/$segment'),
        headers: const {'user-agent': _userAgent},
        followRedirects: false,
      ),
    );
    final location = response.header('location');
    final target = location == null ? null : Uri.https('www.douyu.com', '/').resolve(location);
    final rid = target?.pathSegments.where((s) => s.isNotEmpty).firstOrNull;
    if (response.status >= 300 && response.status < 400 && rid != null && RegExp(r'^\d+$').hasMatch(rid)) {
      return RoomRef(_site, rid);
    }
    throw NotFound(_site, 'alias $segment did not redirect to a room');
  }
}
