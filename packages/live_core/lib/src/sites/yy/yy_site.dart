import 'dart:async';
import 'dart:convert';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/yy/yy_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'yy';
const _host = 'www.yy.com';

final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');

/// Channel numbers: positive decimals without leading zeros.
final RegExp _channelPattern = RegExp(r'^[1-9]\d{0,15}$');

/// The YY adapter (3.x's `YYSite`; parsing in [YyApi]).
///
/// API requests carry 3.x's browser headers and the user's cookie when one
/// is stored; there is no anonymous session. By default streams come from
/// the anonymous mobile HLS route, what 3.x users got (3.x meant
/// stream-manager to come first, but its request never worked), and
/// stream-manager (FLV) stands in when mobile HLS has nothing; [flvFirst]
/// turns the order round. FLV qualities carry every CDN line of their
/// stream. Failures are `SiteError`s; nothing is disguised as an offline
/// room.
final class YySite extends LiveSite
    with LiveSiteLinks
    implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver, LivePlayUrlResolver {
  /// Creates the adapter. [_cookies] holds the user's cookie, if any;
  /// [flvFirst] lists stream-manager's qualities first (see there); [now]
  /// (the stream-manager sequence and the leases) is injectable for tests.
  new(this.http, {this._cookies, this.flvFirst = false, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  /// Whether qualities come from stream-manager (FLV: lower latency, the
  /// platform's names 蓝光, 高清, 流畅, URLs signed for 10 minutes) with
  /// mobile HLS standing in, instead of mobile HLS first (3.x's
  /// `高清 · 720p`, `流畅 · 360p`). Off until the player renews URLs by their
  /// `PlayLease` (M7); the quality ids change with it
  /// ([YyApi.flvQualityId]).
  final bool flvFirst;

  final CookieVault? _cookies;
  final DateTime Function() _now;

  /// The page of each area (by area id), from the catalog.
  final Map<String, Uri> _areaPages = {};

  /// The listing module of each area whose page was read (null: none).
  final Map<String, YyModule?> _modules = {};

  /// Area names by `biz`, learnt from the area modules seen so far (read
  /// from a page, or stored in a followed area's `shortName`); the first
  /// area of a `biz` names it (3.x's `bizAreaNameMap`).
  final Map<String, String> _areaNames = {};

  /// The canonical channel of each room id whose room page was read (a
  /// short number's differs from it), most recent last.
  final Map<String, YyRoomData> _channels = {};

  /// How many room ids [_channels] keeps.
  static const int _channelLimit = 4096;

  @override
  String get id => _site;

  @override
  String get name => 'YY 直播';

  // Requests ------------------------------------------------------------------

  /// The user's cookie ('' when none), control characters removed.
  String _login() => (_cookies?.cookieFor(_site) ?? '').replaceAll(_controlCharacters, '').trim();

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  /// A GET with 3.x's API headers, or [headers].
  Future<LiveResponse> _get(Uri url, {Map<String, String>? headers}) => _send(
    LiveRequest(
      site: _site,
      url: url,
      headers: headers ?? YyApi.apiHeaders(cookie: _login()),
    ),
  );

  // Catalog and search --------------------------------------------------------

  /// The categories of the header and their areas from `getCategory`: four
  /// requests. An area's listing module is read from its page when the
  /// area is opened ([_module]), not here (3.x read all 18 area pages to
  /// fill `shortName`); areas come without `shortName`, and followed areas
  /// that stored one (3.x's) still open without reading their page.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    final response = await _get(Uri.https(_host, '/yyweb/module/data/header'));
    final tabs = YyApi.categoryTabs(response.text, status: response.status);
    final listings = await Future.wait([for (final tab in tabs) _areas(tab.id, tab.name)]);
    return [
      for (final (index, tab) in tabs.indexed)
        LiveCategory(id: tab.id, name: tab.name, children: [for (final entry in listings[index]) entry.area]),
    ];
  }

  /// The areas of category [id] and their pages, remembered for [_module].
  Future<List<({LiveArea area, Uri? page})>> _areas(String id, String name) async {
    final response = await _get(Uri.https(_host, '/c/yycom/category/getCategory.action', {'parentId': id}));
    final areas = YyApi.areas(response.text, categoryId: id, categoryName: name, status: response.status);
    for (final (:area, :page) in areas) {
      if (page != null) _areaPages[area.areaId] = page;
    }
    return areas;
  }

  /// The page of [area] (found in its category's `getCategory` when the
  /// catalog was not loaded).
  Future<Uri> _areaPage(LiveArea area) async {
    final id = area.areaId.trim();
    if (!_areaPages.containsKey(id) && area.areaType.trim().isNotEmpty) {
      await _areas(area.areaType.trim(), area.typeName);
    }
    return _areaPages[id] ?? (throw NotFound(_site, 'area $id is not in category ${area.areaType}'));
  }

  /// The HTML of an area [page].
  Future<String> _readPage(Uri page) async {
    final response = await _get(page);
    if (response.status >= 500) throw NetworkFailure(_site, 'area page ${page.path}: HTTP ${response.status}');
    if (response.status < 200 || response.status >= 300) {
      throw ApiChanged(_site, 'area page ${page.path}: HTTP ${response.status}');
    }
    return response.text;
  }

  /// An area without a JSON listing: a page whose `pageInfo` has none, or
  /// no `pageInfo` at all (小视频, a short-video page; 3.x sent `page.action`
  /// without a module and got HTTP 400).
  static const YyModule _noListing = (moduleId: 0, biz: 'null', subBiz: 'null');

  /// The listing module of [area]: its stored `shortName` (3.x's areas and
  /// follows), else the one read from its page, else its page is read now.
  /// The page of an area without listing is kept for its first page of
  /// rooms ([_pages]).
  Future<YyModule> _module(LiveArea area) async {
    final stored = YyApi.moduleOf(area.shortName);
    if (stored != null) return _learn(stored, area);
    final id = area.areaId.trim();
    if (!_modules.containsKey(id)) {
      final html = await _readPage(await _areaPage(area));
      final module = _modules[id] = YyApi.pageInfo(html);
      if (module == null || !YyApi.hasListing(module)) _pages[id] = html;
    }
    return _learn(_modules[id] ?? _noListing, area);
  }

  /// Area pages just read for their module whose rooms are in the page;
  /// taken by the next [getCategoryRooms].
  final Map<String, String> _pages = {};

  /// [module], its `biz` now naming [area] for recommendations and details
  /// (the first area of a `biz` wins).
  YyModule _learn(YyModule module, LiveArea area) {
    final name = area.areaName.trim();
    if (name.isNotEmpty && YyApi.hasListing(module)) _areaNames.putIfAbsent(module.biz, () => name);
    return module;
  }

  /// `more/page.action` with the area's module (for an area without one 3.x
  /// sent the page alone and got HTTP 400). An area without a JSON listing
  /// (`moduleId: 0`: 手机直播, 综合, 英雄联盟) renders its rooms in its page:
  /// the first page lists those cards (the page read for the module, else
  /// read again), later pages are empty. 3.x (and M4.6) listed nothing
  /// there although the site shows the rooms.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final module = await _module(category);
    if (!YyApi.hasListing(module)) {
      if (page > 1) return const [];
      final html = _pages.remove(category.areaId.trim()) ?? await _readPage(await _areaPage(category));
      return YyApi.pageRooms(html, area: category.areaName);
    }
    final response = await _get(
      Uri.https(_host, '/more/page.action', {
        'page': '${page < 1 ? 1 : page}',
        'pageSize': '$pageSize',
        'moduleId': '${module.moduleId}',
        'biz': module.biz,
        'subBiz': module.subBiz,
      }),
    );
    return YyApi.roomList(response.text, area: category.areaName, status: response.status);
  }

  /// The home listing (`biz=other`); cards name their area by `biz` when an
  /// area module taught it, else leave it empty (3.x showed the raw `biz`,
  /// `other` on every card).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    final response = await _get(
      Uri.https(_host, '/more/page.action', {
        'page': '${page < 1 ? 1 : page}',
        'pageSize': '$pageSize',
        'biz': 'other',
        'subBiz': 'idx',
        'moduleId': '-1',
      }),
    );
    return YyApi.roomList(response.text, areaNames: Map.of(_areaNames), status: response.status);
  }

  /// Live rooms (`t=120`, 16 a page). A blank keyword gives nothing without
  /// a request.
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final response = await _search(keyword, '120', page);
    return response == null ? const [] : YyApi.searchRooms(response.text, status: response.status);
  }

  /// Streamers (`t=1`), live or not.
  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async {
    final response = await _search(keyword, '1', page);
    return response == null ? const [] : YyApi.searchAnchors(response.text, status: response.status);
  }

  Future<LiveResponse?> _search(String keyword, String tab, int page) async {
    final text = keyword.trim();
    if (text.isEmpty) return null;
    return await _get(
      Uri.https(_host, '/apiSearch/doSearch.json', {'q': text, 't': tab, 'n': '${page < 1 ? 1 : page}'}),
    );
  }

  // Rooms ---------------------------------------------------------------------

  /// `liveInfoDetail` of the channel (under its canonical number once the
  /// room page named it). When it is not live (`data: null`, also the
  /// answer for unknown channels and short numbers) the room page tells
  /// them apart: the 404 page is `NotFound`, a short number is looked up
  /// again under its canonical channel, anything else is offline with the
  /// page's streamer, title and danmaku arguments.
  ///
  /// Room entry ([always]) reads the page every time. A refresh, recording
  /// or state check reads it once per room id and adapter (the channel is
  /// remembered); after that an offline room is 3.x's, with 3.x's one
  /// request, and `mergeFrom` keeps the stored name and avatar. The room
  /// keeps [roomId] as its identity.
  Future<LiveRoom> _detail(String roomId, {required bool always}) async {
    final id = roomId.trim();
    if (!_channelPattern.hasMatch(id)) throw NotFound(_site, 'room id $id is not a channel number');
    final known = _channels[id];
    final live = await _liveDetail(known?.sid ?? id, requestedId: id);
    if (live != null) return live;
    if (!always && known != null) return YyApi.offlineRoom(requestedId: id, channel: known);
    final response = await _get(Uri.https(_host, '/$id'));
    final page = YyApi.roomPage(response.text, status: response.status);
    _remember(id, YyRoomData(sid: page.sid, ssid: page.ssid));
    if (page.sid != id && known?.sid != page.sid) {
      final canonical = await _liveDetail(page.sid, requestedId: id);
      if (canonical != null) return canonical;
    }
    return YyApi.offlineRoom(requestedId: id, page: page);
  }

  Future<LiveRoom?> _liveDetail(String sid, {required String requestedId}) async {
    final response = await _get(Uri.https(_host, '/api/liveInfoDetail/$sid/$sid/0'));
    return YyApi.liveDetail(response.text, requestedId: requestedId, areaNames: _areaNames, status: response.status);
  }

  void _remember(String roomId, YyRoomData channel) {
    _channels.remove(roomId);
    _channels[roomId] = channel;
    if (_channels.length > _channelLimit) _channels.remove(_channels.keys.first);
  }

  /// The room with its danmaku arguments; an offline one also reads the
  /// room page (see [_detail]).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, always: true);

  /// `liveInfoDetail`, 3.x's one request per follow; an offline room's page
  /// once (see [_detail]), so an unknown channel is `NotFound` and a short
  /// number is followed to its canonical channel (3.x showed both offline
  /// for ever).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, always: false);

  /// Like the refresh; streams are requested by channel, so it holds all a
  /// recording needs.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, always: false);

  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId, always: false)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// The channel [room] plays: its [YyRoomData], else its danmaku
  /// arguments (3.x), else a room page read before, else its id.
  ({String sid, String ssid}) _channel(LiveRoom room) {
    if (room.data case YyRoomData(:final sid, :final ssid)) return (sid: sid, ssid: ssid);
    if (room.danmakuData case YyDanmakuArgs(:final topSid, :final subSid) when topSid > 0) {
      return (sid: '$topSid', ssid: '${subSid > 0 ? subSid : topSid}');
    }
    final id = room.roomId.trim();
    final known = _channels[id];
    return known == null ? (sid: id, ssid: id) : (sid: known.sid, ssid: known.ssid);
  }

  /// One stream-manager request for [gear] on CDN [line] (-1: the server's
  /// choice): a JSON body sent as `text/plain`, anonymous (`uid=0`),
  /// `sequence` the time in milliseconds.
  Future<({Map<String, dynamic> streams, DateTime issuedAt})> _streamManager(
    ({String sid, String ssid}) channel,
    int gear, {
    int line = -1,
  }) async {
    final issuedAt = _now();
    final sequence = issuedAt.millisecondsSinceEpoch;
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('stream-manager.yy.com', '/v3/channel/streams', {
          'uid': '0',
          'cid': channel.sid,
          'sid': channel.ssid,
          'appid': '0',
          'sequence': '$sequence',
          'encode': 'json',
        }),
        method: 'POST',
        headers: YyApi.streamManagerHeaders(channel.sid, channel.ssid, cookie: _login()),
        body: utf8.encode(
          jsonEncode(
            YyApi.streamManagerBody(sid: channel.sid, ssid: channel.ssid, gear: gear, sequence: sequence, line: line),
          ),
        ),
      ),
    );
    return (streams: YyApi.streams(response.text, status: response.status), issuedAt: issuedAt);
  }

  /// The FLV lines of [gear]: stream-manager's answer (the server picks
  /// the line), then the served gear asked again on each other CDN line
  /// of its stream ([YyApi.otherLines], one request each, concurrently). An
  /// extra line that fails or serves another gear is left out.
  Future<LivePlayUrlResolution> _flv(({String sid, String ssid}) channel, int gear) async {
    final answer = await _streamManager(channel, gear);
    final first = YyApi.resolution(answer.streams, issuedAt: answer.issuedAt, cookie: _login());
    final served = int.tryParse('${first.appliedQualityData ?? ''}');
    final others = YyApi.otherLines(answer.streams);
    if (!first.hasSources || served == null || others.isEmpty) return first;
    final extra = await Future.wait([for (final line in others) _otherLine(channel, served, line)]);
    return YyApi.withLines(first, extra.nonNulls);
  }

  Future<LivePlayUrlResolution?> _otherLine(({String sid, String ssid}) channel, int gear, int line) async {
    try {
      final answer = await _streamManager(channel, gear, line: line);
      return YyApi.resolution(answer.streams, issuedAt: answer.issuedAt, cookie: _login());
    } on SiteError {
      return null;
    }
  }

  /// The mobile HLS answer at [rate]; null when the channel has no stream.
  Future<YyMobileHls?> _mobile(({String sid, String ssid}) channel, String rate) async {
    final response = await _get(
      // Built by hand: 3.x sent `callback=` with its empty value.
      Uri.parse('https://interface.yy.com/hls/new/get/${channel.sid}/${channel.ssid}/$rate?source=wapyy&callback='),
      headers: YyApi.mobileHlsHeaders(channel.sid, channel.ssid, cookie: _login()),
    );
    return YyApi.mobileHls(response.text, status: response.status);
  }

  /// The mobile HLS qualities, 3.x users' (`流畅 · 360p`, `高清 · 720p`);
  /// when mobile HLS has none, stream-manager's (FLV, asked at gear 1). With
  /// [flvFirst] the other way round. A channel with neither is
  /// `StreamUnavailable` when a route said it has no stream, else the first
  /// failure is thrown.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    final channel = _channel(detail);
    SiteError? failure;
    var noStream = false;
    for (final route in flvFirst ? [_flvQualities, _mobileQualities] : [_mobileQualities, _flvQualities]) {
      try {
        return await route(channel);
      } on StreamUnavailable {
        noStream = true;
      } on SiteError catch (error) {
        failure ??= error;
      }
    }
    if (noStream || failure == null) throw const StreamUnavailable(_site, 'no stream on mobile HLS or stream-manager');
    throw failure;
  }

  /// stream-manager's qualities (one request at gear 1);
  /// `StreamUnavailable` when it lists none.
  Future<List<LivePlayQuality>> _flvQualities(({String sid, String ssid}) channel) async {
    final qualities = YyApi.qualities((await _streamManager(channel, 1)).streams);
    if (qualities.isEmpty) throw const StreamUnavailable(_site, 'stream-manager: no stream');
    return qualities;
  }

  /// Both mobile rates at once (3.x's `_getMobileHlsQualities`). A rate that
  /// fails is left out; when every rate failed, the first failure is
  /// thrown, and when the answers had no stream, `StreamUnavailable`.
  Future<List<LivePlayQuality>> _mobileQualities(({String sid, String ssid}) channel) async {
    final answers = await Future.wait([for (final rate in YyApi.mobileHlsRates) _mobileAnswer(channel, rate)]);
    final qualities = YyApi.mobileQualities([for (final answer in answers) (rate: answer.rate, hls: answer.hls)]);
    if (qualities.isNotEmpty) return qualities;
    if (answers.every((answer) => answer.error != null)) throw answers.first.error!;
    throw const StreamUnavailable(_site, 'mobile HLS: no stream');
  }

  Future<({String rate, YyMobileHls? hls, SiteError? error})> _mobileAnswer(
    ({String sid, String ssid}) channel,
    String rate,
  ) async {
    try {
      return (rate: rate, hls: await _mobile(channel, rate), error: null);
    } on SiteError catch (error) {
      return (rate: rate, hls: null, error: error);
    }
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality].
  ///
  /// A mobile quality asks the mobile route at its rate (3.x); when that
  /// has no stream or fails, stream-manager plays the same tier as FLV
  /// (4000 is gear 2 高清, 1200 gear 1 流畅, as measured), with its leases
  /// but without confirming a quality. A stream-manager quality asks
  /// stream-manager at its gear, adds the other CDN lines of the served
  /// stream and reports the gear it was served; when that fails or has no
  /// URL, the mobile route at 4000 (quality rate 2000 or more) or 1200 plays
  /// instead, as in 3.x.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final channel = _channel(detail);
    final data = '${quality.data ?? ''}'.trim();
    if (data.isEmpty) throw const StreamUnavailable(_site, 'quality without data');
    if (data.startsWith(YyApi.mobileHlsPrefix)) {
      final rate = data.substring(YyApi.mobileHlsPrefix.length);
      SiteError? failure;
      var noStream = false;
      try {
        final hls = await _mobile(channel, rate);
        if (hls != null) return YyApi.mobileResolution(hls, rate: rate, cookie: _login());
        noStream = true;
      } on SiteError catch (error) {
        failure = error;
      }
      try {
        final resolution = await _flv(channel, (int.tryParse(rate) ?? 0) >= 2000 ? 2 : 1);
        if (resolution.hasSources) return LivePlayUrlResolution.lines(resolution.lines);
        noStream = true;
      } on SiteError catch (error) {
        failure ??= error;
      }
      if (noStream || failure == null) throw StreamUnavailable(_site, 'mobile HLS $rate and stream-manager: no stream');
      throw failure;
    }
    if (int.tryParse(data) case final gear?) {
      try {
        final resolution = await _flv(channel, gear);
        if (resolution.hasSources) return resolution;
      } on SiteError {
        // Mobile HLS below, as in 3.x.
      }
    }
    final rate = quality.sort >= 2000 ? YyApi.mobileHlsRates.last : YyApi.mobileHlsRates.first;
    final hls = await _mobile(channel, rate);
    if (hls == null) throw const StreamUnavailable(_site, 'no stream on stream-manager or mobile HLS');
    return YyApi.mobileResolution(hls, cookie: _login());
  }

  // Links ---------------------------------------------------------------------

  /// A channel page on `yy.com` or a subdomain (`www.yy.com/{sid}`,
  /// `www.yy.com/{sid}/{ssid}`), and the mobile page
  /// `wap.yy.com/mobileweb/{sid}/{ssid}`. Other pages (`/music/`) are not
  /// rooms.
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return null;
    if (!RoomPaths.hostIs(uri.host.toLowerCase(), 'yy.com')) return null;
    final segments = RoomPaths.segments(uri);
    if (segments.isEmpty) return null;
    final id = (segments.first == 'mobileweb' ? segments.elementAtOrNull(1) : segments.first)?.trim();
    return id != null && RoomPaths.isRoomIdentifier(id, _channelPattern) ? id : null;
  }
}
