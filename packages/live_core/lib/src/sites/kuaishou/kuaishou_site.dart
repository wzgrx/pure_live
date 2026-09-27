import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/kuaishou/kuaishou_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'kuaishou';

/// §6 the browser every web request names: one current desktop Chrome on
/// macOS, the same one the play headers name, with client hints that match
/// it (REG-KUAISHOU-019: the legacy random UA turned the macOS version into
/// hyphens, paired Safari, Edge and Linux UAs with a `Google Chrome` hint,
/// and wrote the hint list without quotes).
const _userAgent =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
const _clientHints = '"Chromium";v="140", "Not=A?Brand";v="24", "Google Chrome";v="140"';
const _accept =
    'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,'
    'application/signed-exchange;v=b3';

/// §6 how long an anonymous session is sent before the next room page
/// starts a new one.
const _sessionLifetime = Duration(minutes: 30);

/// §6 the best-effort device report of a new session's `did`.
final Uri _deviceReport = Uri.parse(
  'https://log-sdk.ksapisrv.com/rest/wd/common/log/collect/misc2?v=3.9.49&kpn=KS_GAME_LIVE_PC',
);

/// §1 hosts of the room page `/u/{id}`.
const _pageHosts = {'live.kuaishou.com', 'live.kuaishou.cn'};

/// §1 navigation words that are never a streamer id (legacy link parser).
const _reserved = {
  'search',
  'category',
  'categories',
  'directory',
  'directories',
  'game',
  'games',
  'video',
  'videos',
  'user',
  'users',
  'index',
  'topic',
  'topics',
  'downloads',
  'settings',
  'login',
  'signup',
};

/// The Kuaishou adapter (spec/sites/kuaishou.md): parsing and request URIs
/// from [KuaishouParse], requests over [LiveHttp].
///
/// Cookies (§6, §8): catalog, recommendations and search go without any
/// cookie. Room pages carry the user's cookie when one is configured, else
/// the anonymous session the adapter keeps from the room pages'
/// `Set-Cookie` (`did`, `clientid`, `client_key`, `kpn`, …). Media requests
/// carry only the user's cookie ([KuaishouParse.playHeaders]); the anonymous
/// session never leaves the adapter.
final class KuaishouSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter. [_cookies] holds the user's cookie, if any; [now],
  /// [random] and [sleep] (the search spacing's wait) are injectable for
  /// tests.
  new(this.http, {this._cookies, DateTime Function()? now, Random? random, Future<void> Function(Duration)? sleep})
    : _now = now ?? DateTime.now,
      _random = random ?? Random.secure(),
      _searchHttp = ThrottledHttp(http, minIntervals: {_site: minRequestInterval['search']!}, now: now, sleep: sleep);

  /// ADR 0011 rule 6: the minimum gap between request starts, by endpoint
  /// class.
  ///
  /// Only `search` (`live_api/search/author`) has evidence: about the 12th
  /// request within a minute answers `result` 2 “操作太快了” (spec §3, one
  /// observation), and the limit is counted per endpoint (`search/liveStream`
  /// still answered 10 meanwhile, DIAGNOSIS). Eleven a minute is the edge
  /// (5.5 s); 6 s keeps at most ten starts in any minute. No other endpoint
  /// has an observed limit (22 samples recorded about 6 s apart; the legacy
  /// catalog walk ran unthrottled), and a platform-wide 6 s would stretch the
  /// catalog walk (at least 14 pages) past a minute, so the platform queue
  /// needs no interval.
  ///
  /// `ThrottledHttp` keys its queue by platform and a `LiveRequest` names no
  /// endpoint, so the adapter feeds the `search` entry into its own
  /// `ThrottledHttp` around the injected transport, used for search only.
  static const Map<String, Duration> minRequestInterval = {'search': Duration(seconds: 6)};

  /// Transport.
  final LiveHttp http;
  final CookieVault? _cookies;
  final DateTime Function() _now;
  final Random _random;

  /// [http] spaced by [minRequestInterval] `search`.
  final LiveHttp _searchHttp;

  /// §6 the anonymous session: cookies by name and when it started.
  ({Map<String, String> cookies, DateTime since})? _session;

  /// §6 device reports by `did`; concurrent callers share one request.
  final Map<String, Future<void>> _reports = {};

  @override
  String get id => _site;

  @override
  String get name => '快手直播';

  // ---------------------------------------------------------------- catalog

  @override
  Future<List<Category>> categories() async => [
    for (final top in KuaishouParse.topCategories) Category(id: top.id, name: top.name, areas: await _areas(top.id)),
  ];

  /// §2 every area of [categoryId]: pages follow `hasMore`, and any failing
  /// page fails the catalog (no partial directory). An area repeated on a
  /// later page is dropped; a page with nothing new ends the walk, so a
  /// server that ignored `page` cannot loop it.
  Future<List<Area>> _areas(String categoryId) async {
    final areas = <String, Area>{};
    PageCursor? cursor;
    do {
      final response = await _get(KuaishouParse.categoryUri(categoryId, cursor: cursor), _webHeaders());
      final page = KuaishouParse.areaPage(
        response.text,
        categoryId: categoryId,
        cursor: cursor,
        status: response.status,
      );
      var added = false;
      for (final area in page.items) {
        if (areas.containsKey(area.id)) continue;
        areas[area.id] = area;
        added = true;
      }
      cursor = added ? page.next : null;
    } while (cursor != null);
    return [...areas.values];
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final response = await _get(KuaishouParse.areaRoomsUri(area.id, cursor: cursor), _webHeaders());
    return KuaishouParse.areaRooms(response.text, cursor: cursor, status: response.status);
  }

  /// §2 `home/list` is a single page; a cursor is never issued for it.
  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    if (cursor != null) throw ArgumentError.value(cursor, 'cursor', 'Kuaishou recommendations have one page');
    final response = await _get(Uri.https('live.kuaishou.com', '/live_api/home/list'), _webHeaders());
    return KuaishouParse.recommended(response.text, status: response.status);
  }

  // ----------------------------------------------------------------- search

  /// §3 author search, spaced by [minRequestInterval]. `result` 2 is
  /// [RateLimited] and 10 is [RiskControl]; a blank keyword costs no
  /// request.
  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    final response = await _get(KuaishouParse.searchUri(text, cursor: cursor), {
      ..._webHeaders(),
      'referer': 'https://live.kuaishou.com/search?keyword=${Uri.encodeQueryComponent(text)}',
    }, via: _searchHttp);
    return KuaishouParse.searchPage(response.text, cursor: cursor, status: response.status);
  }

  // ------------------------------------------------------------------- room

  /// §4 the room page. The page has no broadcast title, so pass [from], the
  /// card the user opened: its caption becomes the title, and a `【回放】`
  /// caption marks a live loop room as replay. [from] is ignored unless it
  /// is the same room, and a card whose title is the streamer's name (a
  /// search card: search has no caption) does not replace the bio.
  @override
  Future<RoomDetail> detail(RoomRef ref, {RoomCard? from}) {
    final card = from != null && from.ref == ref ? from : null;
    final caption = card == null || card.title == card.anchorName ? null : card.title;
    return _roomPage(
      ref.roomId,
      (response, userCookie) => KuaishouParse.detail(
        response.text,
        roomId: ref.roomId,
        status: response.status,
        cardTitle: caption,
        userCookie: userCookie != null,
      ),
    );
  }

  /// §6 streams from a freshly fetched room page (never from a card or an
  /// earlier page). Leases only prefetch (`cutsConnection` false); each line
  /// carries the play headers, with the user's cookie only.
  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) => _roomPage(
    room.ref.roomId,
    (response, userCookie) => KuaishouParse.roomStreams(
      response.text,
      roomId: room.ref.roomId,
      issuedAt: _now(),
      quality: quality,
      userCookie: userCookie,
      status: response.status,
    ),
  );

  /// §4/§6 GETs the room page of [roomId] and hands it to [parse] with the
  /// user cookie it carried, if any.
  ///
  /// A user cookie goes alone: no anonymous session, no retry, and a refusal
  /// is `RiskControl(cookieSuspect: true)` (§8, REG-KUAISHOU-008). Anonymous
  /// pages carry the session while it is younger than 30 minutes, and every
  /// answer's `Set-Cookie` feeds it, so the first room page is itself the
  /// session bootstrap GET (anonymous pages work without cookies, §6). A
  /// refused page drops the session it carried, keeps the cookies the refusal
  /// set, reports their `did` (best effort) and is retried once with them.
  Future<T> _roomPage<T>(String roomId, T Function(LiveResponse response, String? userCookie) parse) async {
    final url = KuaishouParse.roomUri(roomId);
    final userCookie = _userCookie();
    if (userCookie != null) return parse(await _get(url, _pageHeaders(userCookie)), userCookie);
    for (var attempt = 0; ; attempt++) {
      final sent = _sessionCookie();
      final response = await _get(url, _pageHeaders(sent));
      try {
        final result = parse(response, null);
        _absorb(response);
        return result;
      } on RiskControl {
        _absorb(response, restart: sent != null);
        final session = _sessionCookie();
        if (attempt > 0 || session == null || session == sent) rethrow;
        await _reportDevice();
      } on SiteError {
        _absorb(response);
        rethrow;
      }
    }
  }

  // ---------------------------------------------------------------- session

  /// §8 the user's cookie: a pasted `Cookie:` prefix and control characters
  /// removed; null when none is configured.
  String? _userCookie() {
    final raw = _cookies?.cookieFor(_site);
    if (raw == null) return null;
    final text = raw
        .replaceFirst(RegExp(r'^\s*cookie:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .trim();
    return text.isEmpty ? null : text;
  }

  /// The anonymous session while it is younger than [_sessionLifetime].
  Map<String, String>? _liveSession() {
    final session = _session;
    if (session == null) return null;
    if (_now().difference(session.since) < _sessionLifetime) return session.cookies;
    _session = null;
    return null;
  }

  /// The anonymous session as a cookie header, or null.
  String? _sessionCookie() {
    final cookies = _liveSession();
    if (cookies == null || cookies.isEmpty) return null;
    return [for (final MapEntry(:key, :value) in cookies.entries) '$key=$value'].join('; ');
  }

  static final _cookieName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");
  static final _cookieUnsafe = RegExp(r'[\x00-\x20\x7F;,]');
  static final _maxAge = RegExp(r'^\s*max-age\s*=\s*(-?\d+)\s*$', caseSensitive: false);

  /// Merges an anonymous room page's `Set-Cookie` into the session; with
  /// [restart] the session starts over from them. A cookie set with an empty
  /// value or `Max-Age` ≤ 0 is removed.
  void _absorb(LiveResponse response, {bool restart = false}) {
    final received = <String, String?>{};
    for (final line in response.headers['set-cookie'] ?? const <String>[]) {
      final parts = line.split(';');
      final separator = parts.first.indexOf('=');
      if (separator <= 0) continue;
      final name = parts.first.substring(0, separator).trim();
      final value = parts.first.substring(separator + 1).trim();
      if (!_cookieName.hasMatch(name) || _cookieUnsafe.hasMatch(value)) continue;
      final expired = parts
          .skip(1)
          .any((attribute) => (int.tryParse(_maxAge.firstMatch(attribute)?.group(1) ?? '') ?? 1) <= 0);
      received[name] = value.isEmpty || expired ? null : value;
    }
    if (received.isEmpty && !restart) return;
    final previous = restart || _liveSession() == null ? null : _session;
    final cookies = {...?previous?.cookies};
    for (final MapEntry(:key, :value) in received.entries) {
      if (value == null) {
        cookies.remove(key);
      } else {
        cookies[key] = value;
      }
    }
    _session = cookies.isEmpty ? null : (cookies: cookies, since: previous?.since ?? _now());
  }

  /// §6 best-effort device report (`misc2`) of the session's `did`, once per
  /// `did`. Whether the site needs it is open (§12.16), so it is only sent
  /// before retrying a refused page, and its failures are ignored.
  Future<void> _reportDevice() async {
    final did = _liveSession()?['did'];
    if (did == null) return;
    await (_reports[did] ??= _sendDeviceReport(did));
  }

  Future<void> _sendDeviceReport(String did) async {
    try {
      await _send(
        LiveRequest(
          site: _site,
          url: _deviceReport,
          method: 'POST',
          headers: const {
            'user-agent': _userAgent,
            'content-type': 'application/json',
            'origin': 'https://live.kuaishou.com',
            'referer': 'https://live.kuaishou.com/',
          },
          body: utf8.encode(jsonEncode(_devicePayload(did))),
        ),
      );
    } on NetworkFailure {
      // Best effort: the retried room page decides.
    } on TransportFailure {
      // Cancelled: forget this report (the future being removed is this
      // call's own), so the next refusal reports again.
      unawaited(_reports.remove(did));
      rethrow;
    }
  }

  /// §6 the legacy `misc2` body: the `did` plus the spec's fixed values.
  Map<String, Object> _devicePayload(String did) {
    const session = '1eb20f88-51ac-4ecf-8dc3-ace5aefcae4f';
    return {
      'common': {
        'identity_package': {'device_id': did, 'global_id': ''},
        'app_package': {'language': 'zh-CN', 'platform': 10, 'container': 'WEB', 'product_name': 'KS_GAME_LIVE_PC'},
        'device_package': {
          'os_version': 'NT 6.1',
          'model': 'Windows',
          'ua':
              'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/86.0.4240.198 Safari/537.36',
        },
        'need_encrypt': 'false',
        'network_package': {'type': 3},
        'h5_extra_attr':
            '{"sdk_name":"webLogger","sdk_version":"3.9.49","sdk_bundle":"log.common.js","app_version_name":"",'
            '"host_product":"","resolution":"1600x900","screen_with":1600,"screen_height":900,'
            '"device_pixel_ratio":1,"domain":"https://live.kuaishou.com"}',
        'global_attr': '{}',
      },
      'logs': [
        {
          'client_timestamp': _now().millisecondsSinceEpoch,
          'client_increment_id': _random.nextInt(8999) + 1000,
          'session_id': session,
          'time_zone': 'GMT+08:00',
          'event_package': {
            'task_event': {
              'type': 1,
              'status': 0,
              'operation_type': 1,
              'operation_direction': 0,
              'session_id': session,
              'url_package': {
                'page': 'GAME_DETAL_PAGE',
                'identity': '5316c78e-f0b6-4be2-a076-c8f9d11ebc0a',
                'page_type': 2,
                'params': '{"game_id":1001,"game_name":"王者荣耀"}',
              },
              'element_package': <String, Object>{},
            },
          },
        },
      ],
    };
  }

  // ------------------------------------------------------------- transport

  /// §6 通用网页头 (catalog, recommendations, search): no cookie.
  static Map<String, String> _webHeaders() => {
    'user-agent': _userAgent,
    'accept': _accept,
    'sec-ch-ua': _clientHints,
    'sec-ch-ua-mobile': '?0',
    'sec-ch-ua-platform': '"macOS"',
    'sec-fetch-dest': 'document',
    'sec-fetch-mode': 'navigate',
    'sec-fetch-site': 'same-origin',
    'sec-fetch-user': '?1',
  };

  /// §6 房间页请求头: the web headers with `;q=0.9` on `accept`, and the
  /// user's cookie or the anonymous session.
  static Map<String, String> _pageHeaders(String? cookie) => {
    ..._webHeaders(),
    'accept': '$_accept;q=0.9',
    'cookie': ?cookie,
  };

  Future<LiveResponse> _send(LiveRequest request, {LiveHttp? via}) async {
    try {
      return await (via ?? http).send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(Uri url, Map<String, String> headers, {LiveHttp? via, bool followRedirects = true}) =>
      _send(
        LiveRequest(site: _site, url: url, headers: headers, followRedirects: followRedirects),
        via: via,
      );

  // ------------------------------------------------------------------ links

  static final _link = RegExp(r'https?://[^\s，。！？、；：“”‘’（）《》【】<>"]+', caseSensitive: false);
  static final _trailing = RegExp(r'''[.,;:!?'")\]}>]+$''');
  static final _idPattern = RegExp(r'^[A-Za-z0-9_-]+$');

  /// §1 links: the first room page `/u/{id}` in the text wins (on
  /// `live.kuaishou.com` or `.cn`; other pages there are not rooms, null).
  /// Without one, a `v.kuaishou.com` share link is followed one redirect,
  /// and only a redirect to a room page counts. Share links that do not lead
  /// to a room page, the mobile page `m.gifshow.com/fw/live/…` and
  /// `www.kuaishou.com/profile/…` are [UnsupportedLink] until samples show
  /// their targets (§1 归一 4), never `NotFound`. Bare ids are not links: any
  /// word matches the id pattern, and other platforms' ids too.
  @override
  Future<RoomRef?> resolve(String input) async {
    final links = [
      for (final match in _link.allMatches(input)) ?Uri.tryParse(match.group(0)!.replaceFirst(_trailing, '')),
    ];
    for (final url in links) {
      if (_roomOf(url) case final ref?) return ref;
    }
    UnsupportedLink? unsupported;
    for (final url in links) {
      final host = url.host.toLowerCase();
      final path = [
        for (final segment in url.pathSegments)
          if (segment.isNotEmpty) segment.toLowerCase(),
      ];
      if (host == 'v.kuaishou.com' && path.isNotEmpty) {
        try {
          return await _followShareLink(url);
        } on UnsupportedLink catch (error) {
          unsupported ??= error;
        }
      } else if (host == 'm.gifshow.com' ||
          (host.endsWith('.chenzhongtech.com') && path.firstOrNull == 'fw') ||
          ((host == 'www.kuaishou.com' || host == 'kuaishou.com') && path.firstOrNull == 'profile')) {
        unsupported ??= UnsupportedLink(_site, '$host/${path.firstOrNull ?? ''}: target format unknown');
      }
    }
    if (unsupported != null) throw unsupported;
    return null;
  }

  /// §1 the streamer id of a room page URL, or null.
  static RoomRef? _roomOf(Uri url) {
    if (!(url.isScheme('http') || url.isScheme('https')) || !_pageHosts.contains(url.host.toLowerCase())) {
      return null;
    }
    final segments = [
      for (final segment in url.pathSegments)
        if (segment.isNotEmpty) segment,
    ];
    if (segments.length < 2 || segments.first.toLowerCase() != 'u') return null;
    final id = segments[1];
    if (!_idPattern.hasMatch(id) || _reserved.contains(id.toLowerCase())) return null;
    try {
      return RoomRef(_site, id);
    } on FormatException {
      return null;
    }
  }

  /// One GET of a share link without following it: a redirect to a room page
  /// is the room; anything else is [UnsupportedLink].
  Future<RoomRef> _followShareLink(Uri url) async {
    final response = await _get(url, const {'user-agent': _userAgent}, followRedirects: false);
    if (response.status >= 500) throw NetworkFailure(_site, 'share link HTTP ${response.status}');
    final location = Uri.tryParse(response.header('location') ?? '');
    final target = location == null || location.toString().isEmpty ? null : url.resolveUri(location);
    if (response.status >= 300 && response.status < 400 && target != null) {
      if (_roomOf(target) case final ref?) return ref;
    }
    final to = target == null ? '' : ' to ${target.host}/${target.pathSegments.firstOrNull ?? ''}';
    throw UnsupportedLink(_site, 'share link HTTP ${response.status}$to');
  }
}
