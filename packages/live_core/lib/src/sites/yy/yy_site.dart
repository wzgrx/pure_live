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
/// is stored; there is no anonymous session. Streams come from
/// stream-manager (FLV), and from the anonymous mobile HLS route when
/// stream-manager has no stream, as in 3.x. Failures are `SiteError`s;
/// nothing is disguised as an offline room.
final class YySite extends LiveSite
    with LiveSiteLinks
    implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver, LivePlayUrlResolver {
  /// Creates the adapter. [_cookies] holds the user's cookie, if any; [now]
  /// (the stream-manager sequence and the leases) is injectable for tests.
  new(this.http, {this._cookies, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final CookieVault? _cookies;
  final DateTime Function() _now;

  /// The page of each area (by area id), from the catalog.
  final Map<String, Uri> _areaPages = {};

  /// The listing module of each area whose page was read (null: none).
  final Map<String, YyModule?> _modules = {};

  /// Area names by `biz`, learnt from the area pages read so far; the first
  /// area of a `biz` names it (3.x's `bizAreaNameMap`).
  final Map<String, String> _areaNames = {};

  /// The canonical channel of each short number seen.
  final Map<String, YyRoomData> _shortIds = {};

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

  /// The categories of the header and their areas from `getCategory`, each
  /// area with the listing module of its page as `shortName` (3.x's
  /// format; follows store it). Area pages are read concurrently; one that
  /// fails leaves its area without `shortName` (it is read again when the
  /// area is opened) instead of dropping the category as 3.x did.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    final response = await _get(Uri.https(_host, '/yyweb/module/data/header'));
    final tabs = YyApi.categoryTabs(response.text, status: response.status);
    final listings = await Future.wait([for (final tab in tabs) _areas(tab.id, tab.name)]);
    final categories = await Future.wait([
      for (final (index, tab) in tabs.indexed)
        Future.wait([for (final entry in listings[index]) _withModule(entry.area, entry.page)])
            .then((areas) => LiveCategory(id: tab.id, name: tab.name, children: areas)),
    ]);
    for (final category in categories) {
      for (final area in category.children) {
        if (YyApi.moduleOf(area.shortName) case final module?) _areaNames.putIfAbsent(module.biz, () => area.areaName);
      }
    }
    return categories;
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

  Future<LiveArea> _withModule(LiveArea area, Uri? page) async {
    if (page == null) return area;
    final YyModule? module;
    try {
      module = await _pageModule(area.areaId, page);
    } on SiteError {
      return area;
    }
    if (module == null) return area;
    return LiveArea(
      platform: area.platform,
      areaType: area.areaType,
      typeName: area.typeName,
      areaId: area.areaId,
      areaName: area.areaName,
      areaPic: area.areaPic,
      shortName: YyApi.shortName(module),
    );
  }

  /// Reads the listing module of area [areaId] from its [page].
  Future<YyModule?> _pageModule(String areaId, Uri page) async {
    final response = await _get(page);
    if (response.status >= 500) throw NetworkFailure(_site, 'area page ${page.path}: HTTP ${response.status}');
    if (response.status < 200 || response.status >= 300) {
      throw ApiChanged(_site, 'area page ${page.path}: HTTP ${response.status}');
    }
    return _modules[areaId] = YyApi.pageInfo(response.text);
  }

  /// The listing module of [area]: its stored `shortName` (3.x's areas and
  /// follows), else the one read from its page, else its page is read now
  /// (found in its category's `getCategory` when the catalog was not
  /// loaded).
  Future<YyModule> _module(LiveArea area) async {
    final stored = YyApi.moduleOf(area.shortName);
    if (stored != null) return stored;
    final id = area.areaId.trim();
    var module = _modules[id];
    if (!_modules.containsKey(id)) {
      if (!_areaPages.containsKey(id) && area.areaType.trim().isNotEmpty) {
        await _areas(area.areaType.trim(), area.typeName);
      }
      final page = _areaPages[id];
      if (page == null) throw NotFound(_site, 'area $id is not in category ${area.areaType}');
      module = await _pageModule(id, page);
      if (module != null) _areaNames.putIfAbsent(module.biz, () => area.areaName);
    }
    if (module == null) throw ApiChanged(_site, 'area $id: its page has no pageInfo');
    return module;
  }

  /// `more/page.action` with the area's module (for an area without one 3.x
  /// sent the page alone and got HTTP 400). An area whose module lists
  /// nothing (`moduleId: 0`, server-rendered) is empty without a request:
  /// the server answers `data: null` there.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final module = await _module(category);
    if (!YyApi.hasListing(module)) return const [];
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
  /// area page taught it, else show the raw `biz`, as in 3.x.
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

  /// `liveInfoDetail` of the channel; when it is not live (`data: null`,
  /// also the answer for unknown channels and short numbers) the room page
  /// tells them apart: the 404 page is `NotFound`, a short number is looked
  /// up again under its canonical channel, anything else is offline with
  /// the page's streamer and title. The room keeps [roomId] as its identity.
  Future<LiveRoom> _detail(String roomId) async {
    final id = roomId.trim();
    if (!_channelPattern.hasMatch(id)) throw NotFound(_site, 'room id $id is not a channel number');
    final known = _shortIds[id];
    final live = await _liveDetail(known?.sid ?? id, requestedId: id);
    if (live != null) return live;
    final response = await _get(Uri.https(_host, '/$id'));
    final page = YyApi.roomPage(response.text, status: response.status);
    if (page.sid != id) {
      _remember(id, YyRoomData(sid: page.sid, ssid: page.ssid));
      if (known?.sid != page.sid) {
        final canonical = await _liveDetail(page.sid, requestedId: id);
        if (canonical != null) return canonical;
      }
    }
    return YyApi.offlineRoom(page, requestedId: id);
  }

  Future<LiveRoom?> _liveDetail(String sid, {required String requestedId}) async {
    final response = await _get(Uri.https(_host, '/api/liveInfoDetail/$sid/$sid/0'));
    return YyApi.liveDetail(response.text, requestedId: requestedId, areaNames: _areaNames, status: response.status);
  }

  void _remember(String shortId, YyRoomData channel) {
    _shortIds.remove(shortId);
    _shortIds[shortId] = channel;
    if (_shortIds.length > 512) _shortIds.remove(_shortIds.keys.first);
  }

  /// The room with its danmaku arguments (live rooms only, as in 3.x).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  /// The same detail: it costs no extra request.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The same detail; streams are requested by channel, so it holds all a
  /// recording needs.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// The channel [room] plays: its [YyRoomData], else its danmaku
  /// arguments (3.x), else a short number seen before, else its id.
  ({String sid, String ssid}) _channel(LiveRoom room) {
    if (room.data case YyRoomData(:final sid, :final ssid)) return (sid: sid, ssid: ssid);
    if (room.danmakuData case YyDanmakuArgs(:final topSid, :final subSid) when topSid > 0) {
      return (sid: '$topSid', ssid: '${subSid > 0 ? subSid : topSid}');
    }
    final id = room.roomId.trim();
    final known = _shortIds[id];
    return known == null ? (sid: id, ssid: id) : (sid: known.sid, ssid: known.ssid);
  }

  /// One stream-manager request for [gear]: a JSON body sent as
  /// `text/plain`, anonymous (`uid=0`), `sequence` the time in milliseconds.
  Future<({Map<String, dynamic> streams, DateTime issuedAt})> _streamManager(
    ({String sid, String ssid}) channel,
    int gear,
  ) async {
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
          jsonEncode(YyApi.streamManagerBody(sid: channel.sid, ssid: channel.ssid, gear: gear, sequence: sequence)),
        ),
      ),
    );
    return (streams: YyApi.streams(response.text, status: response.status), issuedAt: issuedAt);
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

  /// The qualities of stream-manager asked at gear 1 (3.x's request); when
  /// it fails or lists none (some channels refuse the anonymous route with
  /// `ErrAuthNotPass`), the mobile HLS qualities. A channel with neither is
  /// `StreamUnavailable`.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    final channel = _channel(detail);
    try {
      final qualities = YyApi.qualities((await _streamManager(channel, 1)).streams);
      if (qualities.isNotEmpty) return qualities;
    } on SiteError {
      // Mobile HLS below, as in 3.x.
    }
    return await _mobileQualities(channel);
  }

  /// Both mobile rates at once (3.x's `_getMobileHlsQualities`). A rate that
  /// fails is left out; when every rate failed, the first failure is
  /// thrown, and when the answers had no stream, `StreamUnavailable`.
  Future<List<LivePlayQuality>> _mobileQualities(({String sid, String ssid}) channel) async {
    final answers = await Future.wait([for (final rate in YyApi.mobileHlsRates) _mobileAnswer(channel, rate)]);
    final qualities = YyApi.mobileQualities([for (final answer in answers) (rate: answer.rate, hls: answer.hls)]);
    if (qualities.isNotEmpty) return qualities;
    if (answers.every((answer) => answer.error != null)) throw answers.first.error!;
    throw const StreamUnavailable(_site, 'no stream on stream-manager or mobile HLS');
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

  /// The lines of [quality]. A mobile quality asks the mobile route at its
  /// rate. A stream-manager quality asks stream-manager at its gear and
  /// reports the gear it was served; when that fails or has no URL, the
  /// mobile route at 4000 (quality rate 2000 or more) or 1200 plays
  /// instead, as in 3.x.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final channel = _channel(detail);
    final data = '${quality.data ?? ''}'.trim();
    if (data.isEmpty) throw const StreamUnavailable(_site, 'quality without data');
    if (data.startsWith(YyApi.mobileHlsPrefix)) {
      final rate = data.substring(YyApi.mobileHlsPrefix.length);
      final hls = await _mobile(channel, rate);
      if (hls == null) throw StreamUnavailable(_site, 'mobile HLS $rate: no stream');
      return YyApi.mobileResolution(hls, rate: rate, cookie: _login());
    }
    if (int.tryParse(data) case final gear?) {
      try {
        final answer = await _streamManager(channel, gear);
        final resolution = YyApi.resolution(answer.streams, issuedAt: answer.issuedAt, cookie: _login());
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
