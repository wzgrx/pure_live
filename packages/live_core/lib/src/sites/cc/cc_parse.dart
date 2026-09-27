import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'cc';

/// Rows the directory endpoints are asked for (spec/sites/cc.md §2.2).
const ccPageSize = 30;

/// Rows a search page is asked for (spec §3).
const ccSearchPageSize = 20;

/// Pure parsing of NetEase CC responses (spec/sites/cc.md). Every function
/// takes the raw response text and returns domain values or throws a
/// `SiteError`.
abstract final class CcParse {
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

  /// A ccid: a positive decimal number (spec §1).
  static bool isCcid(String value) => RegExp(r'^[1-9]\d{0,15}$').hasMatch(value);

  /// §4 `【重播】` titles are official rebroadcasts: replay, not live.
  static LiveState _liveState(String title) => title.startsWith('【重播】') ? LiveState.replay : LiveState.live;

  /// §2.3 `startat` is Beijing time without a zone (`2026-09-14 14:53:45`).
  static DateTime? _beijingTime(Object? value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$').firstMatch(jsonString(value) ?? '');
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    return DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).subtract(const Duration(hours: 8));
  }

  /// §2.3 the two audience scales of one payload: `hot_score` (alias
  /// `webcc_visitor`, `visitor`, `total_visitor`) is heat, `vision_visitor`
  /// the viewers watching now.
  static Audience _audience(Map<dynamic, dynamic> room) {
    int? first(List<String> keys) {
      for (final key in keys) {
        final value = jsonInt(room[key]);
        if (value != null && value >= 0) return value;
      }
      return null;
    }

    return Audience(
      popularity: first(const ['hot_score', 'webcc_visitor', 'visitor', 'total_visitor']),
      online: first(const ['vision_visitor', 'online_num']),
    );
  }

  /// §2.1 `gamecategory?catetype=0`: the top-level categories (`cate_list`)
  /// in the server's order, without `全部` (0).
  static List<({String id, String name})> categoryNames(String body) {
    final root = _map(_json(body, 'gamecategory'), 'gamecategory');
    if (jsonInt(root['code']) != 0) throw ApiChanged(_site, 'gamecategory code ${root['code']}');
    final info = _map(_map(root['data'], 'gamecategory.data')['category_info'], 'category_info');
    return [
      for (final item in _list(info['cate_list'], 'cate_list'))
        if (item is Map)
          if (jsonInt(item['cate_type']) case final type? when type != 0)
            (id: '$type', name: jsonString(item['name']) ?? '$type'),
    ];
  }

  /// §2.1 `gamecategory?catetype=<id>`: the areas (`game_list`) of one
  /// category, in the server's order.
  static List<Area> areas(String body, {required String categoryId}) {
    final root = _map(_json(body, 'gamecategory'), 'gamecategory');
    if (jsonInt(root['code']) != 0) throw ApiChanged(_site, 'gamecategory code ${root['code']}');
    final info = _map(_map(root['data'], 'gamecategory.data')['category_info'], 'category_info');
    return [
      for (final item in _list(info['game_list'] ?? const [], 'game_list'))
        if (item is Map && jsonString(item['gametype']) != null)
          Area(
            id: jsonString(item['gametype'])!,
            name: decodeHtmlEntities(jsonString(item['name']) ?? ''),
            categoryId: categoryId,
            icon: jsonUrl(item['cover']),
          ),
    ];
  }

  /// §2.2/§2.3 a room of the directory lists (`lives[]`).
  static RoomCard _listCard(Map<dynamic, dynamic> item) {
    final ccid = jsonString(item['cuteid']) ?? jsonString(item['ccid']);
    if (ccid == null || !isCcid(ccid)) throw const ApiChanged(_site, 'lives[].cuteid missing');
    final title = decodeHtmlEntities(jsonString(item['title']) ?? '');
    return RoomCard(
      ref: RoomRef(_site, ccid),
      title: title,
      anchorName: decodeHtmlEntities(jsonString(item['nickname']) ?? ''),
      state: jsonInt(item['status']) == 1 ? _liveState(title) : LiveState.offline,
      cover: jsonUrl(item['cover']) ?? jsonUrl(item['poster']),
      area: jsonString(item['gamename']) ?? jsonString(item['game_name']),
      audience: _audience(item),
      liveSince: _beijingTime(item['startat']),
      avatar: jsonUrl(item['purl']),
    );
  }

  /// §2.2 `api/category/<gametype>/` and §2.3 `api/category/live/`: one
  /// page of live rooms. The page ends on an empty `lives` (the endpoints
  /// report no total). [gametype] checks that the answer is for the area.
  static Page<RoomCard> roomListPage(String body, {required int page, String? gametype}) {
    final root = _map(_json(body, 'category'), 'category');
    if (gametype != null && jsonString(root['gametype']) != gametype) {
      throw ApiChanged(_site, 'category: answered gametype ${root['gametype']} for $gametype');
    }
    final raw = _list(root['lives'] ?? const [], 'lives');
    final rooms = [
      for (final item in raw)
        if (item is Map) _listCard(item),
    ];
    return Page(rooms, next: rooms.isEmpty ? null : PageCursor('${page + 1}'));
  }

  /// §3 `search/anchor/`: streamers matching the keyword, live or not.
  /// `status == 1` is live; the page ends when it is empty or reaches
  /// `count`.
  static Page<RoomCard> searchPage(String body, {required int page}) {
    final root = _map(_json(body, 'search'), 'search');
    final anchors = _map(root['webcc_anchor'], 'webcc_anchor');
    final raw = _list(anchors['result'] ?? const [], 'webcc_anchor.result');
    final rooms = <RoomCard>[
      for (final item in raw)
        if (item is Map)
          if (jsonString(item['cuteid']) case final ccid? when isCcid(ccid)) _searchCard(item, ccid),
    ];
    final count = jsonInt(anchors['count']) ?? 0;
    final more = rooms.isNotEmpty && page * ccSearchPageSize < count;
    return Page(rooms, next: more ? PageCursor('${page + 1}') : null);
  }

  static RoomCard _searchCard(Map<dynamic, dynamic> item, String ccid) {
    final live = jsonInt(item['status']) == 1;
    final title = decodeHtmlEntities(jsonString(item['title']) ?? '');
    final heat = jsonInt(item['hot_score']);
    return RoomCard(
      ref: RoomRef(_site, ccid),
      title: title,
      anchorName: decodeHtmlEntities(jsonString(item['nickname']) ?? ''),
      state: live ? _liveState(title) : LiveState.offline,
      cover: live ? jsonUrl(item['cover']) : null,
      area: jsonString(item['game_name']),
      audience: live && heat != null && heat > 0 ? Audience(popularity: heat) : Audience.none,
      liveSince: live ? _beijingTime(item['startat']) : null,
      avatar: jsonUrl(item['portraiturl']) ?? jsonUrl(item['portrait']),
    );
  }

  /// §4 `activitylives/anchor/lives`: the live channel of [ccid], or null
  /// when the anchor is not broadcasting (or does not exist; the endpoint
  /// answers both with only `is_black`). A non-numeric id is a 400.
  static String? liveChannel(String body, {required String ccid, int status = 200}) {
    if (status == 400) throw NotFound(_site, 'activitylives rejected ccid $ccid');
    final root = _map(_json(body, 'activitylives'), 'activitylives');
    if (jsonString(root['code']) != 'OK') throw ApiChanged(_site, 'activitylives code ${root['code']}');
    final data = _map(root['data'], 'activitylives.data');
    final anchor = data[ccid];
    if (anchor is! Map) throw ApiChanged(_site, 'activitylives: no entry for $ccid');
    return jsonString(anchor['channel_id']);
  }

  static Map<String, String> _danmakuKeys(Map<dynamic, dynamic> room, String ccid) => {
    'ccid': ccid,
    'channelId': ?jsonString(room['channel_id']) ?? jsonString(room['cid']),
    'roomId': ?jsonString(room['room_id']) ?? jsonString(room['roomid']),
    'gametype': ?jsonString(room['gametype']),
  };

  /// §4 `live/channel/?channelids=`: the live room of the channel [ccid]
  /// broadcasts in. Returns null when the channel answers `nolive` (the
  /// broadcast ended between the two requests).
  static RoomDetail? channelDetail(String body, {required String ccid}) {
    final root = _map(_json(body, 'live/channel'), 'live/channel');
    final rooms = _list(root['data'], 'live/channel.data');
    if (rooms.isEmpty) throw const ApiChanged(_site, 'live/channel: empty data');
    final room = _map(rooms.first, 'live/channel.data[0]');
    if (jsonInt(room['nolive']) == 1) return null;
    final id = jsonString(room['ccid']) ?? jsonString(room['cuteid']);
    if (id != ccid) throw ApiChanged(_site, 'live/channel answered ccid $id for $ccid');
    final title = decodeHtmlEntities(jsonString(room['title']) ?? '');
    final live = jsonInt(room['status']) == 1;
    final notice = jsonString(room['personal_label']);
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, ccid),
        title: title,
        anchorName: decodeHtmlEntities(jsonString(room['nickname']) ?? ''),
        state: live ? _liveState(title) : LiveState.offline,
        cover: jsonUrl(room['cover']) ?? jsonUrl(room['poster']),
        area: jsonString(room['gamename']),
        audience: _audience(room),
        liveSince: live ? _beijingTime(room['startat']) : null,
      ),
      link: Uri.parse('https://cc.163.com/$ccid/'),
      avatar: jsonUrl(room['purl']),
      notice: notice == null ? null : decodeHtmlEntities(notice),
      danmakuKeys: _danmakuKeys(room, ccid),
    );
  }

  static final _nextData = RegExp(r'<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)</script>');

  /// §4 the room page (`cc.163.com/<ccid>/?…platform=ds`) of an anchor that
  /// is not broadcasting: `roomInfoInitData.code == 404` (`no ccid`) is an
  /// unknown ccid, anything else the anchor's offline room.
  static RoomDetail pageDetail(String body, {required String ccid}) {
    final match = _nextData.firstMatch(body);
    if (match == null) throw const ApiChanged(_site, 'room page: no __NEXT_DATA__');
    final data = _map(_json(match.group(1)!, 'room page'), 'room page');
    final props = _map(_map(data['props'], 'props')['pageProps'], 'pageProps');
    final info = _map(props['roomInfoInitData'], 'roomInfoInitData');
    if (jsonInt(info['code']) == 404) throw NotFound(_site, 'room page: ${jsonString(info['reason']) ?? 'no ccid'}');
    final anchor = info['micfirst'] is Map ? info['micfirst'] as Map : const <String, dynamic>{};
    final live = info['live'] is Map ? info['live'] as Map : const <String, dynamic>{};
    final id = jsonString(anchor['ccid']) ?? jsonString(info['ccid']) ?? jsonString(live['ccid']);
    if (id != ccid) throw ApiChanged(_site, 'room page answered ccid $id for $ccid');
    final name = jsonString(anchor['nickname']) ?? jsonString(info['nickname']);
    if (name == null) throw const ApiChanged(_site, 'room page: no nickname');
    final title = jsonString(info['live_title']) ?? jsonString(live['title']) ?? '';
    final announcement = jsonString(info['announcement']);
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, ccid),
        title: decodeHtmlEntities(title),
        anchorName: decodeHtmlEntities(name),
        state: LiveState.offline,
        area: jsonString(info['gamename']) ?? jsonString(live['gamename']),
      ),
      link: Uri.parse('https://cc.163.com/$ccid/'),
      avatar: jsonUrl(anchor['portraiturl']) ?? jsonUrl(anchor['purl']) ?? jsonUrl(info['purl']),
      notice: announcement == null ? null : decodeHtmlEntities(announcement),
      danmakuKeys: {
        'ccid': ccid,
        'channelId': ?jsonString(info['channel_id']) ?? jsonString(live['channel_id']),
        'roomId': ?jsonString(info['room_id']) ?? jsonString(live['room_id']),
      },
    );
  }

  /// §6 `video_play_url` → its object; `410 Gone` (`no live`) is an anchor
  /// without a stream.
  static Map<String, dynamic> playData(String body, {int status = 200}) {
    if (status == 410 || status == 404) throw StreamUnavailable(_site, 'video_play_url HTTP $status');
    if (status >= 500) throw NetworkFailure(_site, 'video_play_url HTTP $status');
    if (status != 200) throw ApiChanged(_site, 'video_play_url HTTP $status');
    return _map(_json(body, 'video_play_url'), 'video_play_url');
  }

  /// §5.1 qualities: `vbrname_list` in server order (best first), labels
  /// from `vbrname_mapping`.
  static List<Quality> qualities(Map<String, dynamic> data) {
    final names = _list(data['vbrname_list'] ?? const [], 'vbrname_list');
    final mapping = data['vbrname_mapping'] is Map ? data['vbrname_mapping'] as Map : const <String, dynamic>{};
    final ids = [for (final name in names) ?jsonString(name)];
    if (ids.isEmpty) {
      final selected = jsonString(data['vbrname_sel']);
      if (selected == null) throw const ApiChanged(_site, 'video_play_url: no qualities');
      ids.add(selected);
    }
    return [
      for (final (index, id) in ids.indexed)
        Quality(id: id, label: jsonString(mapping[id]) ?? id, rank: ids.length - index),
    ];
  }

  /// §5.3 the quality the server delivered: `vbrname_sel`.
  static String? confirmedQuality(Map<String, dynamic> data) => jsonString(data['vbrname_sel']);

  /// §5.2 the CDN codes the room can be pulled from, in server order.
  static List<String> cdns(Map<String, dynamic> data) => [
    for (final code in (data['cdn_list'] as List?) ?? const []) ?jsonString(code),
  ];

  /// §5.2 the lines of one answer: `videourl` on `cdn_sel`, then
  /// `bakvideourl` on `bakcdn_sel`.
  static List<({String cdn, Uri url})> lines(Map<String, dynamic> data) {
    final result = <({String cdn, Uri url})>[];
    for (final (urlKey, cdnKey) in const [('videourl', 'cdn_sel'), ('bakvideourl', 'bakcdn_sel')]) {
      final url = jsonUrl(data[urlKey]);
      if (url == null) continue;
      result.add((cdn: jsonString(data[cdnKey]) ?? url.host, url: url));
    }
    return result;
  }

  /// §6.2 the stream container by the URL path.
  static StreamFormat format(Uri url) => url.path.toLowerCase().endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv;

  /// §6.3 lease of a URL received at [issuedAt]: the first field of
  /// `auth_key` (`<unix seconds>-rand-uid-md5`) is when the CDN stops
  /// accepting new connections; an established connection keeps flowing
  /// (420 s held past a 300 s key, 2026-09-27). Refresh one minute (at most
  /// a quarter of the lifetime) early. No key or one already past: null.
  static Lease? lease(Uri url, DateTime issuedAt) {
    final key = url.queryParameters['auth_key'];
    final expiry = key == null ? null : int.tryParse(key.split('-').first);
    if (expiry == null) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final lead = lifetime ~/ 4 < const Duration(minutes: 1) ? lifetime ~/ 4 : const Duration(minutes: 1);
    return Lease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt, cutsConnection: false);
  }
}
