import 'dart:async';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/soop/soop_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';
import 'package:live_net/live_net.dart';

const _site = 'soop';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// §2.1 the single top-level group; id and name kept from 3.x so saved
/// areas stay under the same category.
const _categoryId = '1';

/// §2.1 more pages than the catalog has ever had (5 of 120 in 2026-09).
const _maxCategoryPages = 20;

/// §1 hosts of SOOP (formerly AfreecaTV) pages.
const _hosts = ['sooplive.co.kr', 'sooplive.com', 'afreecatv.com'];

/// The SOOP adapter (spec/sites/soop.md): parsing from [SoopParse], requests
/// over [LiveHttp]. The user's cookie, when one is stored, goes with the
/// player API (it unlocks age-restricted broadcasts, spec §8).
final class SoopSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter.
  new(this.http, {this._cookies});

  /// Transport.
  final LiveHttp http;
  final CookieVault? _cookies;

  @override
  String get id => _site;

  @override
  String get name => 'SOOP';

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(Uri url, {String referer = 'https://www.sooplive.co.kr/'}) async {
    final response = await _send(
      LiveRequest(site: _site, url: url, headers: {'user-agent': _userAgent, 'referer': referer}),
    );
    if (response.status >= 500 && response.status != 515) {
      throw NetworkFailure(_site, '${url.path} HTTP ${response.status}');
    }
    return response;
  }

  static int _page(PageCursor? cursor) => int.tryParse(cursor?.value ?? '') ?? 1;

  static Uri _search(Map<String, String> query) => Uri.https('sch.sooplive.co.kr', '/api.php', query);

  @override
  Future<List<Category>> categories() async {
    final areas = <Area>[];
    for (var page = 1; page <= _maxCategoryPages; page++) {
      final response = await _get(
        _search({
          'm': 'categoryList',
          'szKeyword': '',
          'szOrder': 'view_cnt',
          'nPageNo': '$page',
          'nListCnt': '$soopCategoryPageSize',
          'nOffset': '0',
          'szPlatform': 'pc',
        }),
      );
      final result = SoopParse.categoryPage(response.text, categoryId: _categoryId);
      areas.addAll(result.areas);
      if (!result.more || result.areas.isEmpty) break;
    }
    return [Category(id: _categoryId, name: '热门', areas: areas)];
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    final page = _page(cursor);
    final response = await _get(
      _search({
        'm': 'categoryContentsList',
        'szType': 'live',
        'nPageNo': '$page',
        'nListCnt': '$soopAreaPageSize',
        'szPlatform': 'pc',
        'szOrder': 'view_cnt_desc',
        'szCateNo': area.id,
      }),
    );
    return SoopParse.areaPage(response.text, page: page, area: area.name);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    final page = _page(cursor);
    final response = await _get(
      Uri.https('live.sooplive.co.kr', '/api/main_broad_list_api.php', {
        'selectType': 'action',
        'selectValue': 'all',
        'orderType': 'view_cnt',
        'pageNo': '$page',
        'lang': 'ko_KR',
      }),
    );
    return SoopParse.mainPage(response.text, page: page);
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    final page = _page(cursor);
    final response = await _get(
      _search({
        'l': 'DF',
        'm': 'liveSearch',
        'c': 'UTF-8',
        'w': 'webk',
        'isMobile': '0',
        'onlyParent': '1',
        'szType': 'json',
        'szOrder': 'score',
        'szKeyword': text,
        'nPageNo': '$page',
        'nListCnt': '$soopSearchPageSize',
        'tab': 'live',
        'location': 'total_search',
        'isHashSearch': '0',
        'v': '2.0',
      }),
    );
    return SoopParse.searchPage(response.text, page: page);
  }

  /// §4/§6.3 `player_live_api.php`; [type] `live` or `aid`.
  Future<LiveResponse> _player(String bj, {required String type, String bno = '', String quality = 'HD'}) {
    final cookie = _cookies?.cookieFor(_site)?.trim();
    return _send(
      LiveRequest.form(
        site: _site,
        url: Uri.https('live.sooplive.co.kr', '/afreeca/player_live_api.php', {'bjid': bj}),
        headers: {
          'user-agent': _userAgent,
          'referer': 'https://play.sooplive.co.kr/$bj',
          'origin': 'https://play.sooplive.co.kr',
          if (cookie != null && cookie.isNotEmpty) 'cookie': cookie,
        },
        fields: {
          'bid': bj,
          'bno': bno,
          'type': type,
          'pwd': '',
          'player_type': 'html5',
          'stream_type': 'common',
          'quality': quality,
          'mode': 'landing',
          'from_api': '0',
          'is_revive': 'false',
        },
      ),
    );
  }

  Future<SoopStation> _station(String bj) async {
    final response = await _get(
      Uri.https('chapi.sooplive.co.kr', '/api/$bj/station'),
      referer: 'https://ch.sooplive.co.kr/',
    );
    return SoopParse.station(response.text, status: response.status);
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final bj = ref.roomId.toLowerCase();
    if (!SoopParse.isBroadcaster(bj)) throw NotFound(_site, 'not a broadcaster id: $bj');
    final player = await _player(bj, type: 'live');
    final answer = SoopParse.channel(player.text, status: player.status);
    if (answer.result == 1) {
      // The station adds viewers, avatar and the station title; a failing
      // station request leaves them out.
      SoopStation? station;
      try {
        station = await _station(bj);
      } on SiteError {
        station = null;
      }
      return SoopParse.liveDetail(answer.channel, id: bj, station: station);
    }
    // §4 RESULT 0 is offline or unknown; -6 is an age-restricted broadcast.
    return SoopParse.stationDetail(await _station(bj), id: bj);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final bj = room.ref.roomId.toLowerCase();
    final player = await _player(bj, type: 'live');
    final answer = SoopParse.channel(player.text, status: player.status);
    final channel = answer.channel;
    switch (answer.result) {
      case 1:
        break;
      case -6:
        throw const NeedsLogin(_site, 'player_live_api RESULT -6 (age-restricted)');
      case 0:
        throw const StreamUnavailable(_site, 'player_live_api RESULT 0 (not broadcasting)');
      default:
        throw ApiChanged(_site, 'player_live_api RESULT ${answer.result}');
    }
    if (jsonString(channel['BPWD']) == 'Y') throw const StreamUnavailable(_site, 'password-protected broadcast');
    final bno = jsonString(channel['BNO']);
    final rmd = jsonUrl(channel['RMD']);
    final cdn = jsonString(channel['CDN']);
    if (bno == null || rmd == null || cdn == null) throw const ApiChanged(_site, 'CHANNEL without BNO, RMD or CDN');
    final qualities = SoopParse.qualities(channel);
    if (qualities.isEmpty) throw const StreamUnavailable(_site, 'no VIEWPRESET');
    final requested = quality ?? qualities.first;
    final assign = await _get(
      rmd.replace(
        path: '/broad_stream_assign.html',
        queryParameters: {'return_type': SoopParse.returnType(cdn), 'broad_key': '$bno-common-${requested.id}-hls'},
      ),
      referer: 'https://play.sooplive.co.kr/',
    );
    final playlist = SoopParse.assignedPlaylist(assign.text);
    final aidResponse = await _player(bj, type: 'aid', bno: bno, quality: requested.id);
    final aid = SoopParse.aid(aidResponse.text, status: aidResponse.status);
    final url = playlist.replace(queryParameters: {...playlist.queryParameters, 'aid': aid});
    return StreamSet(
      qualities: qualities,
      selected: requested,
      lines: [
        StreamLine(
          url: url,
          format: SoopParse.format(url),
          lineId: cdn,
          requested: requested,
          headers: const {
            'user-agent': _userAgent,
            'referer': 'https://play.sooplive.co.kr/',
            'origin': 'https://play.sooplive.co.kr',
          },
          codec: 'avc',
        ),
      ],
    );
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (SoopParse.isBroadcaster(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    if (!_hosts.any((root) => host == root || host.endsWith('.$root'))) return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final candidate = segments.firstOrNull == 'station' ? segments.elementAtOrNull(1) : segments.firstOrNull;
    final bj = candidate?.toLowerCase();
    return bj != null && SoopParse.isBroadcaster(bj) && !_reserved.contains(bj) ? RoomRef(_site, bj) : null;
  }

  /// §1 path words that are pages, not broadcasters.
  static const _reserved = {'search', 'directory', 'category', 'login', 'live', 'vod', 'main', 'my', 'all'};
}
