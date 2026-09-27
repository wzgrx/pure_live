import 'dart:async';
import 'dart:convert';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/yy/yy_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'yy';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// §6.1 the web player's stream SDK version.
const _sdkVersion = '5.23.0-beta.2';

/// The YY adapter (spec/sites/yy.md): parsing from [YyParse], requests over
/// [LiveHttp]. The user's cookie, when one is stored, goes with the API
/// requests as the legacy client sent it (spec §8); media requests never
/// carry it.
final class YySite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [now] is injectable for tests.
  new(this.http, {this._cookies, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;
  final CookieVault? _cookies;
  final DateTime Function() _now;

  /// §2.1 area page URL by area id, from the header.
  final Map<String, Uri> _areaPages = {};

  /// §2.2 listing module by area id (null: the area has none).
  final Map<String, YyModule?> _modules = {};

  /// §2.3 area names by `biz`, learnt from the modules resolved so far.
  final Map<String, String> _areaNames = {};

  @override
  String get id => _site;

  @override
  String get name => 'YY直播';

  Map<String, String> _headers({String referer = 'https://www.yy.com/'}) {
    final cookie = _cookies?.cookieFor(_site)?.trim();
    return {'user-agent': _userAgent, 'referer': referer, if (cookie != null && cookie.isNotEmpty) 'cookie': cookie};
  }

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(Uri url, {Map<String, String>? headers}) async {
    final response = await _send(LiveRequest(site: _site, url: url, headers: headers ?? _headers()));
    if (response.status >= 500) throw NetworkFailure(_site, '${url.path} HTTP ${response.status}');
    return response;
  }

  static int _page(PageCursor? cursor) => int.tryParse(cursor?.value ?? '') ?? 1;

  Future<List<({Category category, Map<String, Uri> pages})>> _header() async {
    final response = await _get(Uri.https('www.yy.com', '/yyweb/module/data/header'));
    final header = YyParse.header(response.text);
    for (final entry in header) {
      _areaPages.addAll(entry.pages);
    }
    return header;
  }

  @override
  Future<List<Category>> categories() async {
    final header = await _header();
    final icons = await Future.wait([
      for (final entry in header)
        _get(Uri.https('www.yy.com', '/c/yycom/category/getCategory.action', {'parentId': entry.category.id}))
            .then((response) => YyParse.areaIcons(response.text)),
    ]);
    return [
      for (final (index, entry) in header.indexed)
        Category(
          id: entry.category.id,
          name: entry.category.name,
          areas: [
            for (final area in entry.category.areas)
              Area(id: area.id, name: area.name, categoryId: area.categoryId, icon: icons[index][area.id]),
          ],
        ),
    ];
  }

  /// §2.2 the listing module of [area]: its page URL from the header, then
  /// the page's `pageInfo`.
  Future<YyModule?> _module(Area area) async {
    if (_modules.containsKey(area.id)) return _modules[area.id];
    if (!_areaPages.containsKey(area.id)) await _header();
    final page = _areaPages[area.id];
    if (page == null) throw NotFound(_site, 'no area ${area.id}');
    final response = await _get(page);
    final module = YyParse.module(response.text);
    _modules[area.id] = module;
    if (module != null) _areaNames[module.biz] = area.name;
    return module;
  }

  Future<Page<RoomCard>> _list(YyModule module, int page, {String? area}) async {
    final response = await _get(
      Uri.https('www.yy.com', '/more/page.action', {
        'page': '$page',
        'pageSize': '$yyPageSize',
        'biz': module.biz,
        'subBiz': module.subBiz,
        'moduleId': module.moduleId,
      }),
    );
    return YyParse.roomListPage(response.text, page: page, area: area, areaNames: _areaNames);
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final module = await _module(area);
    // §2.2 areas without a listing module (their pages are server-rendered).
    if (module == null) return const Page.empty();
    return await _list(module, _page(cursor), area: area.name);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) =>
      _list((moduleId: '-1', biz: 'other', subBiz: 'idx'), _page(cursor));

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    final page = _page(cursor);
    final response = await _get(
      Uri.https('www.yy.com', '/apiSearch/doSearch.json', {'q': text, 't': '120', 'n': '$page'}),
    );
    return YyParse.searchPage(response.text, page: page);
  }

  Future<RoomDetail?> _liveDetail(String sid) async {
    final response = await _get(Uri.https('www.yy.com', '/api/liveInfoDetail/$sid/$sid/0'));
    return YyParse.liveDetail(response.text, sid: sid, areaNames: _areaNames);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final sid = ref.roomId;
    if (!YyParse.isChannel(sid)) throw NotFound(_site, 'not a channel number: $sid');
    final live = await _liveDetail(sid);
    if (live != null) return live;
    // §4 not broadcasting, unknown, or a short channel number (asid): the
    // room page tells them apart and names the canonical sid.
    final page = await _get(Uri.https('www.yy.com', '/$sid'));
    final room = YyParse.roomPage(page.text);
    if (room.sid != sid) {
      final canonical = await _liveDetail(room.sid);
      if (canonical != null) return canonical;
    }
    return YyParse.offlineDetail(page.text);
  }

  /// §6.1 one stream-manager request for [gear] on [line] (-1: the
  /// server's choice).
  Future<({YyStreams streams, DateTime issuedAt})> _streams(
    String sid,
    String ssid, {
    required String gear,
    int line = -1,
  }) async {
    final issuedAt = _now();
    final sequence = issuedAt.millisecondsSinceEpoch;
    final body = {
      'head': {
        'seq': sequence,
        'appidstr': '0',
        'bidstr': '121',
        'cidstr': sid,
        'sidstr': ssid,
        'uid64': 0,
        'client_type': 108,
        'client_ver': _sdkVersion,
        'stream_sys_ver': 1,
        'app': 'yylive_web',
        'playersdk_ver': _sdkVersion,
        'thundersdk_ver': '0',
        'streamsdk_ver': _sdkVersion,
      },
      'client_attribute': {
        'client': 'web',
        'model': 'web0',
        'cpu': '',
        'graphics_card': '',
        'os': 'chrome',
        'osversion': '140.0.0.0',
        'vsdk_version': '',
        'app_identify': '',
        'app_version': '',
        'business': '',
        'width': '1920',
        'height': '1080',
        'scale': '',
        'client_type': 8,
        'h265': 0,
      },
      'avp_parameter': {
        'version': 1,
        'client_type': 8,
        'service_type': 0,
        'imsi': 0,
        'send_time': sequence ~/ 1000,
        'line_seq': line,
        'gear': int.tryParse(gear) ?? 1,
        'ssl': 1,
        'stream_format': 0,
      },
    };
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('stream-manager.yy.com', '/v3/channel/streams', {
          'uid': '0',
          'cid': sid,
          'sid': ssid,
          'appid': '0',
          'sequence': '$sequence',
          'encode': 'json',
        }),
        method: 'POST',
        // §6.1 the web SDK sends the JSON as text/plain; some channels refuse
        // application/json before looking at the body (legacy yy_site.dart:347).
        headers: {
          ..._headers(referer: 'https://www.yy.com/$sid/$ssid'),
          'origin': 'https://www.yy.com',
          'content-type': 'text/plain;charset=UTF-8',
        },
        body: utf8.encode(jsonEncode(body)),
      ),
    );
    return (streams: YyParse.streams(response.text, status: response.status), issuedAt: issuedAt);
  }

  static const Map<String, String> _mediaHeaders = {'user-agent': _userAgent, 'referer': 'https://www.yy.com/'};

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final sid = room.danmakuKeys['sid'] ?? room.ref.roomId;
    final ssid = room.danmakuKeys['ssid'] ?? sid;
    final first = await _streams(sid, ssid, gear: quality?.id ?? '1');
    final qualities = first.streams.qualities;
    if (qualities.isEmpty || first.streams.url == null) return await _mobileHls(sid, ssid);
    final requested = quality ?? qualities.first;
    final answer = requested.id == (quality?.id ?? '1') ? first : await _streams(sid, ssid, gear: requested.id);
    final answers = [answer];
    // §5.2 the other lines of the delivered stream, one request each, at the
    // gear the server delivered (asking again for an unavailable gear would
    // only be answered with the same substitute).
    final delivered = answer.streams.gear ?? requested.id;
    for (final line in answer.streams.lines) {
      if (line == answer.streams.line) continue;
      try {
        answers.add(await _streams(sid, ssid, gear: delivered, line: line));
      } on SiteError {
        // One line failing leaves the others (spec §9).
      }
    }
    final seen = <String>{};
    final lines = <StreamLine>[
      for (final result in answers)
        if (result.streams.url case final url?)
          if (seen.add('${result.streams.line ?? url.host}'))
            StreamLine(
              url: url,
              format: YyParse.format(url),
              lineId: '${result.streams.line ?? url.host}',
              requested: requested,
              confirmed: qualities.where((q) => q.id == result.streams.gear).firstOrNull,
              headers: _mediaHeaders,
              lease: YyParse.lease(url, result.issuedAt),
            ),
    ];
    if (lines.isEmpty) throw const ApiChanged(_site, 'stream-manager: no playable URL');
    return StreamSet(qualities: qualities, selected: requested, lines: lines);
  }

  /// §6.4 the anonymous mobile HLS route, for channels whose stream-manager
  /// answer has no web line.
  Future<StreamSet> _mobileHls(String sid, String ssid) async {
    final response = await _get(
      Uri.https('interface.yy.com', '/hls/new/get/$sid/$ssid/1200', {'source': 'wapyy', 'callback': ''}),
      headers: {..._headers(referer: 'https://wap.yy.com/mobileweb/$sid/$ssid')},
    );
    final url = YyParse.mobileHls(response.text);
    if (url == null) throw const StreamUnavailable(_site, 'no stream on stream-manager or mobile HLS');
    const quality = Quality(id: 'mobile-1200', label: '流畅', rank: 1);
    return StreamSet(
      qualities: const [quality],
      selected: quality,
      lines: [
        StreamLine(
          url: url,
          format: StreamFormat.hls,
          lineId: 'mobile-hls',
          requested: quality,
          headers: _mediaHeaders,
        ),
      ],
    );
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (YyParse.isChannel(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    if (host != 'yy.com' && !host.endsWith('.yy.com')) return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final channel = segments.firstOrNull == 'mobileweb' ? segments.elementAtOrNull(1) : segments.firstOrNull;
    return channel != null && YyParse.isChannel(channel) ? RoomRef(_site, channel) : null;
  }
}
