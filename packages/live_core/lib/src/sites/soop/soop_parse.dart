import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'soop';

/// Rows a category list page is asked for (spec/sites/soop.md §2.1).
const soopCategoryPageSize = 120;

/// Rows an area page is asked for (spec §2.2).
const soopAreaPageSize = 60;

/// Rows a search page is asked for (spec §3).
const soopSearchPageSize = 30;

/// What `player_live_api` (type=live) says about a broadcaster (spec §4).
typedef SoopChannel = ({int result, Map<String, dynamic> channel});

/// The station API's broadcaster and live broadcast (spec §4).
typedef SoopStation = ({String nick, String? introduction, Uri? avatar, Map<String, dynamic>? broad});

/// Pure parsing of SOOP responses (spec/sites/soop.md). Every function takes
/// the raw response text and returns domain values or throws a `SiteError`.
abstract final class SoopParse {
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

  /// A broadcaster id (the room id): letters, digits and `_`, lower case.
  static bool isBroadcaster(String value) => RegExp(r'^[a-z0-9_]{3,30}$').hasMatch(value);

  static Uri? _image(Object? value) {
    var text = jsonString(value);
    if (text == null) return null;
    if (text.startsWith('//')) text = 'https:$text';
    return jsonUrl(text);
  }

  /// §2.2 `2026-09-22 19:59:31` (optionally `.0`) is Korean time (UTC+9).
  static DateTime? _koreanTime(Object? value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})').firstMatch(jsonString(value) ?? '');
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    return DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).subtract(const Duration(hours: 9));
  }

  /// §2.5 viewers watching now: `total_view_cnt`, else `view_cnt`, else the
  /// PC and mobile counts added.
  static int? _viewers(Map<dynamic, dynamic> item) {
    final total = jsonInt(item['total_view_cnt']) ?? jsonInt(item['view_cnt']) ?? jsonInt(item['current_sum_viewer']);
    if (total != null) return total;
    final pc = jsonInt(item['pc_view_cnt']);
    final mobile = jsonInt(item['mobile_view_cnt']);
    return pc == null && mobile == null ? null : (pc ?? 0) + (mobile ?? 0);
  }

  /// §2.1 `m=categoryList`: one page of categories (the areas of the single
  /// top-level group); `is_more` says whether another page follows.
  static ({List<Area> areas, bool more}) categoryPage(String body, {required String categoryId}) {
    final root = _map(_json(body, 'categoryList'), 'categoryList');
    final data = _map(root['data'], 'categoryList.data');
    return (
      areas: [
        for (final item in _list(data['list'] ?? const [], 'categoryList.list'))
          if (item is Map && jsonString(item['category_no']) != null)
            Area(
              id: jsonString(item['category_no'])!,
              name: jsonString(item['category_name']) ?? '',
              categoryId: categoryId,
              icon: _image(item['cate_img']),
            ),
      ],
      more: data['is_more'] == true,
    );
  }

  static RoomCard _card(Map<dynamic, dynamic> item, {String? title, Uri? cover, String? area}) {
    final id = jsonString(item['user_id']);
    if (id == null) throw const ApiChanged(_site, 'room without user_id');
    return RoomCard(
      ref: RoomRef(_site, id.toLowerCase()),
      title: decodeHtmlEntities(title ?? jsonString(item['broad_title']) ?? ''),
      anchorName: decodeHtmlEntities(jsonString(item['user_nick']) ?? ''),
      state: LiveState.live,
      cover: cover,
      area: area,
      audience: Audience(online: _viewers(item)),
      liveSince: _koreanTime(item['broad_start']),
      avatar: _image(item['user_profile_img']) ?? avatar(id),
    );
  }

  /// §1 the profile image path every list and page uses.
  static Uri? avatar(String id) {
    final bj = id.toLowerCase();
    if (bj.length < 2) return null;
    return Uri.parse('https://stimg.sooplive.co.kr/LOGO/${bj.substring(0, 2)}/$bj/$bj.jpg');
  }

  /// §2.2 `m=categoryContentsList`: live rooms of an area; `is_more` says
  /// whether another page follows.
  static Page<RoomCard> areaPage(String body, {required int page, String? area}) {
    final root = _map(_json(body, 'categoryContentsList'), 'categoryContentsList');
    final data = _map(root['data'], 'categoryContentsList.data');
    final rooms = [
      for (final item in _list(data['list'] ?? const [], 'categoryContentsList.list'))
        if (item is Map) _card(item, cover: _image(item['thumbnail']), area: area),
    ];
    final more = rooms.isNotEmpty && data['is_more'] == true;
    return Page(rooms, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §2.3 `main_broad_list_api.php`: live rooms by viewers; the page ends
  /// on an empty `broad`.
  static Page<RoomCard> mainPage(String body, {required int page}) {
    final root = _map(_json(body, 'main_broad_list'), 'main_broad_list');
    final rooms = [
      for (final item in _list(root['broad'] ?? const [], 'broad'))
        if (item is Map) _card(item, cover: _image(item['broad_thumb']), area: jsonString(item['category_name'])),
    ];
    return Page(rooms, next: rooms.isEmpty ? null : PageCursor('${page + 1}'));
  }

  /// §3 `m=liveSearch`: live rooms matching the keyword; the page ends on an
  /// empty `REAL_BROAD` (`HAS_MORE_LIST` stays true on empty pages).
  static Page<RoomCard> searchPage(String body, {required int page}) {
    final root = _map(_json(body, 'liveSearch'), 'liveSearch');
    final rooms = [
      for (final item in _list(root['REAL_BROAD'] ?? const [], 'REAL_BROAD'))
        if (item is Map)
          _card(
            item,
            cover: _image(item['broad_img']),
            area: jsonString(item['broad_cate_name']) ?? jsonString(item['standard_broad_cate_name']),
          ),
    ];
    final more = rooms.isNotEmpty && root['HAS_MORE_LIST'] != false;
    return Page(rooms, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §4 `player_live_api.php` (type=live or aid): `CHANNEL` and its
  /// `RESULT` (1 live, 0 not broadcasting or unknown, -6 login needed).
  static SoopChannel channel(String body, {int status = 200}) {
    if (status >= 500) throw NetworkFailure(_site, 'player_live_api HTTP $status');
    final root = _map(_json(body, 'player_live_api'), 'player_live_api');
    final channel = _map(root['CHANNEL'], 'CHANNEL');
    final result = jsonInt(channel['RESULT']);
    if (result == null) throw const ApiChanged(_site, 'CHANNEL.RESULT missing');
    return (result: result, channel: channel);
  }

  /// §4 the station API (`chapi …/station`): the broadcaster, and the live
  /// broadcast when there is one. HTTP 515 `code 9000` is an unknown id.
  static SoopStation station(String body, {int status = 200}) {
    final root = _json(body, 'station');
    if (root is Map && jsonInt(root['code']) == 9000) throw NotFound(_site, 'station: ${root['message']}');
    if (status >= 500) throw NetworkFailure(_site, 'station HTTP $status');
    final map = _map(root, 'station');
    final station = _map(map['station'], 'station.station');
    final nick = jsonString(station['user_nick']);
    if (nick == null) throw const ApiChanged(_site, 'station.user_nick missing');
    final broad = map['broad'];
    return (
      nick: nick,
      introduction: jsonString(station['station_title']),
      avatar: _image(map['profile_image']),
      broad: broad is Map<String, dynamic> ? broad : null,
    );
  }

  /// §4 a live broadcast from `player_live_api` (RESULT 1), with the
  /// station's figures when known.
  static RoomDetail liveDetail(Map<String, dynamic> channel, {required String id, SoopStation? station}) {
    final bj = (jsonString(channel['BJID']) ?? id).toLowerCase();
    final bno = jsonString(channel['BNO']);
    final tags = channel['CATEGORY_TAGS'];
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, bj),
        title: decodeHtmlEntities(jsonString(channel['TITLE']) ?? ''),
        anchorName: decodeHtmlEntities(jsonString(channel['BJNICK']) ?? station?.nick ?? ''),
        state: LiveState.live,
        cover: bno == null ? null : Uri.parse('https://liveimg.sooplive.co.kr/m/$bno'),
        area: tags is List && tags.isNotEmpty ? jsonString(tags.first) : null,
        audience: Audience(online: station?.broad == null ? null : _viewers(station!.broad!)),
      ),
      link: Uri.parse('https://play.sooplive.co.kr/$bj'),
      avatar: station?.avatar ?? avatar(bj),
      introduction: station?.introduction,
      danmakuKeys: {
        'bj': bj,
        'bno': ?bno,
        'chatNo': ?jsonString(channel['CHATNO']),
        'chatHost': ?(jsonString(channel['CHDOMAIN']) ?? _chatHost(jsonString(channel['CHIP']))),
        'chatPort': ?jsonString(channel['CHPT']),
      },
    );
  }

  /// §7.1 `chat-<IP in hex>.sooplive.com` when only `CHIP` is given.
  static String? _chatHost(String? ip) {
    final parts = ip?.split('.').map(int.tryParse).toList();
    if (parts == null || parts.length != 4 || parts.any((part) => part == null || part < 0 || part > 255)) return null;
    return 'chat-${parts.map((part) => part!.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}.sooplive.com';
  }

  /// §4 a broadcaster from the station API alone: live when the station has
  /// a broadcast (an age-restricted one: `player_live_api` answers -6), else
  /// offline.
  static RoomDetail stationDetail(SoopStation station, {required String id}) {
    final bj = id.toLowerCase();
    final broad = station.broad;
    final bno = broad == null ? null : jsonString(broad['broad_no']);
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, bj),
        title: decodeHtmlEntities(broad == null ? '' : jsonString(broad['broad_title']) ?? ''),
        anchorName: decodeHtmlEntities(station.nick),
        state: broad == null ? LiveState.offline : LiveState.live,
        cover: bno == null ? null : Uri.parse('https://liveimg.sooplive.co.kr/m/$bno'),
        audience: Audience(online: broad == null ? null : _viewers(broad)),
      ),
      link: Uri.parse('https://play.sooplive.co.kr/$bj'),
      avatar: station.avatar ?? avatar(bj),
      introduction: station.introduction,
      danmakuKeys: {'bj': bj, 'bno': ?bno},
    );
  }

  /// §5.1 `VIEWPRESET`: the qualities without `auto`, best first (by bps,
  /// then resolution).
  static List<Quality> qualities(Map<String, dynamic> channel) {
    final presets = <({String name, String label, int bps, int height})>[];
    final seen = <String>{};
    for (final item in (channel['VIEWPRESET'] as List?) ?? const []) {
      if (item is! Map) continue;
      final name = jsonString(item['name']);
      if (name == null || name == 'auto' || !seen.add(name)) continue;
      presets.add((
        name: name,
        label: jsonString(item['label']) ?? name,
        bps: jsonInt(item['bps']) ?? 0,
        height: jsonInt(item['label_resolution']) ?? 0,
      ));
    }
    presets.sort((a, b) => b.bps != a.bps ? b.bps.compareTo(a.bps) : b.height.compareTo(a.height));
    return [
      for (final (index, preset) in presets.indexed)
        Quality(id: preset.name, label: preset.label, rank: presets.length - index),
    ];
  }

  /// §6.2 `broad_stream_assign.html`: the playlist URL.
  static Uri assignedPlaylist(String body) {
    final root = _map(_json(body, 'broad_stream_assign'), 'broad_stream_assign');
    final url = jsonUrl(root['view_url']);
    if (jsonString(root['result']) != '1' || url == null) {
      throw ApiChanged(_site, 'broad_stream_assign result ${root['result']}');
    }
    return url;
  }

  /// §6.3 `player_live_api` type=aid: the stream key; -6 needs a login.
  static String aid(String body, {int status = 200}) {
    final answer = channel(body, status: status);
    if (answer.result == -6) throw const NeedsLogin(_site, 'aid: RESULT -6 (age-restricted)');
    final aid = jsonString(answer.channel['AID']);
    if (answer.result != 1 || aid == null) throw StreamUnavailable(_site, 'aid: RESULT ${answer.result}');
    return aid;
  }

  /// §6.2 the `return_type` of the stream assignment for a `CDN` code.
  static String returnType(String cdn) {
    if (cdn.contains('gs_cdn')) return 'gs_cdn_pc_web';
    if (cdn.contains('lg_cdn')) return 'lg_cdn_pc_web';
    return cdn;
  }

  /// §6.4 the stream's container.
  static StreamFormat format(Uri url) => url.path.toLowerCase().endsWith('.flv') ? StreamFormat.flv : StreamFormat.hls;
}
