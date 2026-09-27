import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'yy';

/// Rooms a directory page is asked for (spec/sites/yy.md §2.2).
const yyPageSize = 30;

/// What the listing endpoint needs for one area (the area page's `pageInfo`).
typedef YyModule = ({String moduleId, String biz, String subBiz});

/// One stream-manager answer, reduced to what the adapter uses (spec §6).
typedef YyStreams = ({List<Quality> qualities, String? gear, Uri? url, int? line, List<int> lines});

/// Pure parsing of YY responses (spec/sites/yy.md). Every function takes the
/// raw response text and returns domain values or throws a `SiteError`.
abstract final class YyParse {
  static Object? _json(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  static Map<String, dynamic> _map(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    throw ApiChanged(_site, '$what: expected an object');
  }

  static List<dynamic> _list(Object? value, String what) {
    if (value is List) return value;
    throw ApiChanged(_site, '$what: expected a list');
  }

  /// A YY channel number (sid, or the short `asid`).
  static bool isChannel(String value) => RegExp(r'^[1-9]\d{0,15}$').hasMatch(value);

  /// §2 images come as `http://` or protocol-relative; both are served over
  /// https.
  static Uri? _image(Object? value) {
    var text = jsonString(value);
    if (text == null) return null;
    if (text.startsWith('//')) text = 'https:$text';
    if (text.startsWith('http://')) text = 'https://${text.substring(7)}';
    return jsonUrl(text);
  }

  /// §2.1 `yyweb/module/data/header`: the top-level categories and their
  /// areas (`navs`) with the area page URL each.
  static List<({Category category, Map<String, Uri> pages})> header(String body) {
    final root = _map(_json(body, 'header'), 'header');
    final result = <({Category category, Map<String, Uri> pages})>[];
    for (final tab in _list(root['categoryTabs'], 'categoryTabs')) {
      final id = tab is Map ? jsonString(tab['id']) : null;
      if (tab is! Map || id == null) continue;
      final areas = <Area>[];
      final pages = <String, Uri>{};
      for (final nav in (tab['navs'] as List?) ?? const []) {
        final areaId = nav is Map ? jsonString(nav['id']) : null;
        if (nav is! Map || areaId == null) continue;
        areas.add(Area(id: areaId, name: jsonString(nav['title']) ?? '', categoryId: id));
        final page = _image(nav['url']);
        if (page != null) pages[areaId] = page;
      }
      result.add((category: Category(id: id, name: jsonString(tab['title']) ?? id, areas: areas), pages: pages));
    }
    return result;
  }

  /// §2.1 `getCategory.action?parentId=`: area covers by area id.
  static Map<String, Uri> areaIcons(String body) {
    final root = _map(_json(body, 'getCategory'), 'getCategory');
    return {
      for (final item in (root['data'] as List?) ?? const [])
        if (item is Map && jsonString(item['id']) != null) jsonString(item['id'])!: ?_image(item['cover']),
    };
  }

  static final _pageInfo = RegExp(r'pageInfo\s*=\s*(\{[\s\S]*?\})\s*;');

  /// §2.2 the area page's `pageInfo` (`moduleId`, `biz`, `subBiz`); null
  /// when the page has no listing module (`moduleId: 0`, `biz: 'null'`).
  static YyModule? module(String html) {
    final source = _pageInfo.firstMatch(html)?.group(1);
    if (source == null) throw const ApiChanged(_site, 'area page: no pageInfo');
    final moduleId = RegExp(r'''moduleId\s*:\s*['"]?(-?\d+)''').firstMatch(source)?.group(1);
    final biz = RegExp(r'''\bbiz\s*:\s*['"]([^'"]*)''').firstMatch(source)?.group(1);
    final subBiz = RegExp(r'''subBiz\s*:\s*['"]([^'"]*)''').firstMatch(source)?.group(1);
    if (moduleId == null || moduleId == '0' || biz == null || biz.isEmpty || biz == 'null') return null;
    if (subBiz == null || subBiz.isEmpty || subBiz == 'null') return null;
    return (moduleId: moduleId, biz: biz, subBiz: subBiz);
  }

  static RoomCard _card(Map<dynamic, dynamic> item, {required String title, String? area}) {
    final sid = jsonString(item['sid']);
    if (sid == null || !isChannel(sid)) throw const ApiChanged(_site, 'room without sid');
    final start = jsonInt(item['startTime']);
    return RoomCard(
      ref: RoomRef(_site, sid),
      title: decodeHtmlEntities(title),
      anchorName: decodeHtmlEntities(jsonString(item['name']) ?? ''),
      state: LiveState.live,
      cover: _image(item['thumb2']) ?? _image(item['thumb']),
      area: area,
      audience: Audience(popularity: jsonInt(item['users'])),
      liveSince: start == null || start <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(start * 1000, isUtc: true),
      avatar: _image(item['avatar']),
    );
  }

  /// §2.2/§2.3 `more/page.action`: one page of live rooms. The page ends on
  /// an empty `data` or when `page × pageSize` reaches `totalCount`.
  /// [area] names the area; [areaNames] maps a room's `biz` otherwise.
  static Page<RoomCard> roomListPage(
    String body, {
    required int page,
    String? area,
    Map<String, String> areaNames = const {},
  }) {
    final root = _map(_json(body, 'page.action'), 'page.action');
    if (jsonInt(root['resultCode']) != 0) throw ApiChanged(_site, 'page.action resultCode ${root['resultCode']}');
    final data = _map(root['data'], 'page.action.data');
    final raw = _list(data['data'] ?? const [], 'page.action.data.data');
    final rooms = [
      for (final item in raw)
        if (item is Map)
          _card(item, title: jsonString(item['desc']) ?? '', area: area ?? areaNames[jsonString(item['biz'])]),
    ];
    final total = jsonInt(data['totalCount']) ?? 0;
    final more = rooms.isNotEmpty && page * yyPageSize < total;
    return Page(rooms, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §3 `apiSearch/doSearch.json?t=120`: live rooms matching the keyword.
  /// The page ends on empty `docs` or at `totalPage`.
  static Page<RoomCard> searchPage(String body, {required int page}) {
    final root = _map(_json(body, 'doSearch'), 'doSearch');
    final data = _map(root['data'], 'doSearch.data');
    final result = _map(data['searchResult'], 'searchResult');
    final response = _map(result['response'], 'searchResult.response');
    final section = response['120'];
    final docs = section is Map ? _list(section['docs'] ?? const [], 'docs') : const <Object?>[];
    final rooms = <RoomCard>[
      for (final item in docs)
        if (item is Map && jsonString(item['sid']) != null)
          RoomCard(
            ref: RoomRef(_site, jsonString(item['sid'])!),
            title: decodeHtmlEntities(_searchTitle(item)),
            anchorName: decodeHtmlEntities(jsonString(item['name']) ?? ''),
            state: jsonString(item['liveOn']) == '1' ? LiveState.live : LiveState.offline,
            cover: _image(item['posterurl']),
            audience: Audience(popularity: jsonInt(item['users'])),
            avatar: _image(item['headurl']),
          ),
    ];
    final pages = jsonInt(data['totalPage']) ?? 0;
    return Page(rooms, next: rooms.isNotEmpty && page < pages ? PageCursor('${page + 1}') : null);
  }

  /// §3 `channelName` reads `<stage name> 正在直播`; the suffix is not a title.
  static String _searchTitle(Map<dynamic, dynamic> item) {
    final name = jsonString(item['channelName']) ?? '';
    return name.endsWith(' 正在直播') ? name.substring(0, name.length - ' 正在直播'.length) : name;
  }

  /// §4 `api/liveInfoDetail/<sid>/<sid>/0`: the live room, or null when the
  /// channel is not broadcasting (or does not exist: both answer `data: null`).
  static RoomDetail? liveDetail(String body, {required String sid, Map<String, String> areaNames = const {}}) {
    final root = _map(_json(body, 'liveInfoDetail'), 'liveInfoDetail');
    if (jsonInt(root['resultCode']) != 0) throw ApiChanged(_site, 'liveInfoDetail resultCode ${root['resultCode']}');
    final data = root['data'];
    if (data == null) return null;
    final item = _map(data, 'liveInfoDetail.data');
    final canonical = jsonString(item['sid']) ?? sid;
    final ssid = jsonString(item['ssid']) ?? canonical;
    final card = _card(item, title: jsonString(item['desc']) ?? '', area: areaNames[jsonString(item['biz'])]);
    return RoomDetail(
      card: card,
      link: Uri.parse('https://www.yy.com/$canonical'),
      avatar: card.avatar,
      danmakuKeys: {'sid': canonical, 'ssid': ssid},
    );
  }

  /// §1/§4 the room page `www.yy.com/<sid or asid>`: the canonical channel
  /// (`pageInfo.sid`, `ssid`) and the anchor. The 404 page (`yycom_404`) is
  /// an unknown channel.
  static ({String sid, String ssid, String? name, Uri? avatar, String? title, String? area}) roomPage(String html) {
    if (html.contains('yycom_404')) throw const NotFound(_site, 'room page is the 404 page');
    final source = _pageInfo.firstMatch(html)?.group(1);
    if (source == null) throw const ApiChanged(_site, 'room page: no pageInfo');
    String? field(String name) => RegExp('\\b$name\\s*:\\s*"([^"]*)"').firstMatch(source)?.group(1);
    String? decoded(String name) {
      final match = RegExp('\\b$name\\s*:\\s*decodeURIComponent\\("([^"]*)"\\)').firstMatch(source)?.group(1);
      return match == null ? field(name) : _percentDecode(match);
    }

    final sid = field('sid');
    if (sid == null || !isChannel(sid)) throw const ApiChanged(_site, 'room page: no sid');
    final ssid = field('ssid');
    return (
      sid: sid,
      ssid: ssid != null && isChannel(ssid) ? ssid : sid,
      name: jsonString(field('nick')),
      avatar: _image(field('logo')),
      title: jsonString(decoded('roomName')),
      area: jsonString(RegExp(r'stringBiz\s*:\s*"([^"]*)"').firstMatch(source)?.group(1)),
    );
  }

  /// `decodeURIComponent` without throwing: a malformed escape stays as
  /// written, malformed UTF-8 becomes U+FFFD.
  static String _percentDecode(String text) {
    final bytes = <int>[];
    for (var i = 0; i < text.length; i++) {
      final byte = text[i] == '%' && i + 2 < text.length ? int.tryParse(text.substring(i + 1, i + 3), radix: 16) : null;
      if (byte != null) {
        bytes.add(byte);
        i += 2;
      } else {
        bytes.addAll(utf8.encode(text[i]));
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// §4 the room of a channel that is not broadcasting, from [roomPage].
  static RoomDetail offlineDetail(String html) {
    final page = roomPage(html);
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, page.sid),
        title: page.title ?? '',
        anchorName: page.name ?? '',
        state: LiveState.offline,
        area: page.area,
      ),
      link: Uri.parse('https://www.yy.com/${page.sid}'),
      avatar: page.avatar,
      danmakuKeys: {'sid': page.sid, 'ssid': page.ssid},
    );
  }

  /// §6.2 a `stream-manager` answer: the web-playable qualities, the gear
  /// and URL of the line it returned, and the line numbers of that stream.
  static YyStreams streams(String body, {int status = 200}) {
    if (status >= 500) throw NetworkFailure(_site, 'stream-manager HTTP $status');
    if (status != 200) throw ApiChanged(_site, 'stream-manager HTTP $status');
    final root = _map(_json(body, 'stream-manager'), 'stream-manager');
    final info = root['channel_stream_info'];
    final gears = <String, ({String gear, String name, int seq})>{};
    final gearOfKey = <String, String>{};
    for (final stream in info is Map ? (info['streams'] as List?) ?? const [] : const []) {
      if (stream is! Map) continue;
      final key = jsonString(stream['stream_key']);
      final raw = jsonString(stream['json']);
      if (key == null || raw == null) continue;
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        continue;
      }
      final gearInfo = decoded is Map ? decoded['gear_info'] : null;
      if (gearInfo is! Map) continue;
      final gear = jsonString(gearInfo['gear']);
      if (gear == null) continue;
      gearOfKey[key] = gear;
      gears.putIfAbsent(
        gear,
        () => (gear: gear, name: jsonString(gearInfo['name']) ?? gear, seq: jsonInt(gearInfo['seq']) ?? 0),
      );
    }
    final ordered = gears.values.toList()..sort((a, b) => b.seq.compareTo(a.seq));
    final qualities = [
      for (final (index, gear) in ordered.indexed)
        Quality(id: gear.gear, label: gear.name, rank: ordered.length - index),
    ];
    final avp = root['avp_info_res'];
    final addresses = avp is Map ? avp['stream_line_addr'] : null;
    String? key;
    Uri? url;
    int? line;
    if (addresses is Map && addresses.isNotEmpty) {
      final entry = addresses.entries.first;
      key = '${entry.key}';
      final value = entry.value;
      if (value is Map) {
        final cdn = value['cdn_info'];
        var text = cdn is Map ? jsonString(cdn['url']) : null;
        if (text != null && text.startsWith('//')) text = 'https:$text';
        url = jsonUrl(text);
        line = jsonInt(value['line_seq']) ?? jsonInt(url?.queryParameters['line_seq']);
      }
    }
    final lineList = avp is Map ? avp['stream_line_list'] : null;
    final infos = lineList is Map && key != null && lineList[key] is Map ? (lineList[key] as Map)['line_infos'] : null;
    return (
      qualities: qualities,
      gear: key == null ? null : gearOfKey[key],
      url: url,
      line: line,
      lines: [
        for (final item in infos is List ? infos : const [])
          if (item is Map) ?jsonInt(item['line_seq']),
      ],
    );
  }

  /// §6.4 mobile HLS (`interface.yy.com/hls/new/get`): a JSONP-like
  /// `({…})`; the `hls` URL, or null when the channel has no stream.
  static Uri? mobileHls(String body) {
    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    if (start < 0 || end < start) throw const ApiChanged(_site, 'mobile HLS: no object');
    final data = _map(_json(body.substring(start, end + 1), 'mobile HLS'), 'mobile HLS');
    if (jsonInt(data['code']) != 0) return null;
    return jsonUrl(data['hls']);
  }

  /// §6.3 lease of a FLV URL received at [issuedAt]: `t` is the Unix second
  /// the signature stops opening connections (issue + 600 s); an
  /// established connection keeps flowing (780 s held, 2026-09-27). Refresh
  /// a minute early; no `t` or one already past: null.
  static Lease? lease(Uri url, DateTime issuedAt) {
    final expiry = int.tryParse(url.queryParameters['t'] ?? '');
    if (expiry == null || expiry < 1000000000) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final lead = lifetime ~/ 4 < const Duration(minutes: 1) ? lifetime ~/ 4 : const Duration(minutes: 1);
    return Lease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt, cutsConnection: false);
  }

  /// §6.2 container by the URL path.
  static StreamFormat format(Uri url) => url.path.toLowerCase().endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv;
}
