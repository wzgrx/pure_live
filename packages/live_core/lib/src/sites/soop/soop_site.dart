import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/soop/soop_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'soop';

/// Where the catalog, area lists and search are answered.
const _search = 'sch.sooplive.co.kr';

/// Where the player API and the recommendations are answered.
const _live = 'live.sooplive.co.kr';

/// More catalog pages than the platform has ever had (5 of 120 in 2026-09),
/// so a server that never says "no more" cannot loop the catalog.
const _maxCategoryPages = 20;

final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');

/// Streamer ids (3.x's link rule): letters, digits, `_` and `-`.
final RegExp _roomIdPattern = RegExp(r'^[a-zA-Z0-9_-]+$');

/// Hosts of SOOP pages 3.x recognised. The former `afreecatv.com`, which
/// SOOP's own search answers still link to, is a later upgrade.
const _hosts = ['sooplive.co.kr', 'sooplive.com'];

/// First path segments that are pages there, not streamers (besides
/// [RoomPaths.reservedSegments]).
const _pages = {'live', 'vod', 'main', 'my', 'all', 'player'};

/// The SOOP (formerly AfreecaTV) adapter (3.x's `SoopSite`; parsing in
/// [SoopApi]).
///
/// Every request goes as `soop`, so the app routes the whole platform
/// through its proxy setting; it carries 3.x's API headers and the user's
/// cookie when one is stored (3.x sent it with every request, the media and
/// the danmaku connection). The room page's `player_live_api` answer holds
/// everything streams need; a stream is its assigned playlist with a key
/// (`aid`) asked for per quality. Failures are `SiteError`s; nothing is
/// disguised as an offline room.
final class SoopSite extends LiveSite
    with LiveSiteLinks
    implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver, LivePlayUrlResolver, LivePlayRecoveryResolver {
  /// Creates the adapter. [_cookies] holds the user's cookie, if any; [now]
  /// (the cover's cache buster) is injectable for tests.
  new(this.http, {this._cookies, DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final CookieVault? _cookies;
  final DateTime Function() _now;

  @override
  String get id => _site;

  @override
  String get name => 'SOOP直播';

  // Requests ------------------------------------------------------------------

  /// The user's cookie ('' when signed out), control characters removed.
  String _cookie() => (_cookies?.cookieFor(_site) ?? '').replaceAll(_controlCharacters, '').trim();

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(Uri url) => _send(
    LiveRequest(
      site: _site,
      url: url,
      headers: SoopApi.apiHeaders(cookie: _cookie()),
    ),
  );

  /// `player_live_api.php` for streamer [roomId]: `type` `live` (the room)
  /// or `aid` (the key of broadcast [bno] at [quality]), 3.x's form.
  Future<LiveResponse> _player(String roomId, {required String type, String bno = '', String quality = 'HD'}) => _send(
    LiveRequest.form(
      site: _site,
      url: Uri.https(_live, '/afreeca/player_live_api.php', {'bjid': roomId}),
      headers: SoopApi.apiHeaders(cookie: _cookie()),
      fields: {
        'bid': roomId,
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

  // Catalog and search --------------------------------------------------------

  /// One category (3.x's "热门", id 1) with every area: pages of 120 while
  /// `is_more` says so. A failing first page fails the catalog (3.x showed
  /// an empty one); a later one ends it with the areas so far, as in 3.x.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    final areas = <String, LiveArea>{};
    for (var number = 1; number <= _maxCategoryPages; number++) {
      final ({List<LiveArea> areas, bool hasMore}) result;
      try {
        final response = await _get(
          Uri.https(_search, '/api.php', {
            'm': 'categoryList',
            'szKeyword': '',
            'szOrder': 'view_cnt',
            'nPageNo': '$number',
            'nListCnt': '${SoopApi.categoryPageSize}',
            'nOffset': '0',
            'szPlatform': 'pc',
          }),
        );
        result = SoopApi.categoryPage(response.text, status: response.status);
      } on SiteError {
        if (number == 1) rethrow;
        break;
      }
      var added = false;
      for (final area in result.areas) {
        if (areas.containsKey(area.areaId)) continue;
        areas[area.areaId] = area;
        added = true;
      }
      if (!result.hasMore || !added) break;
    }
    return [
      LiveCategory(id: SoopApi.category.id, name: SoopApi.category.name, children: [...areas.values]),
    ];
  }

  /// Live rooms of [category] by viewers; [pageSize] is sent, limited to
  /// 1–60 (3.x).
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final response = await _get(
      Uri.https(_search, '/api.php', {
        'm': 'categoryContentsList',
        'szType': 'live',
        'nPageNo': '${page < 1 ? 1 : page}',
        'nListCnt': '${pageSize.clamp(1, 60)}',
        'szPlatform': 'pc',
        'szOrder': 'view_cnt_desc',
        'szCateNo': category.areaId,
      }),
    );
    return SoopApi.areaRooms(response.text, areaName: category.areaName, status: response.status);
  }

  /// The whole site by viewers, 60 a page (the platform's size).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    final response = await _get(
      Uri.https(_live, '/api/main_broad_list_api.php', {
        'selectType': 'action',
        'selectValue': 'all',
        'orderType': 'view_cnt',
        'pageNo': '${page < 1 ? 1 : page}',
        'lang': 'ko_KR',
      }),
    );
    return SoopApi.recommendRooms(response.text, status: response.status);
  }

  /// Live search; [pageSize] is sent, limited to 1–50 (3.x). A blank
  /// keyword gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final response = await _get(
      Uri.https(_search, '/api.php', {
        'l': 'DF',
        'm': 'liveSearch',
        'c': 'UTF-8',
        'w': 'webk',
        'isMobile': '0',
        'onlyParent': '1',
        'szType': 'json',
        'szOrder': 'score',
        'szKeyword': text,
        'nPageNo': '${page < 1 ? 1 : page}',
        'nListCnt': '${pageSize.clamp(1, 50)}',
        'tab': 'live',
        'location': 'total_search',
        'isHashSearch': '0',
        'v': '2.0',
      }),
    );
    return SoopApi.searchRooms(response.text, status: response.status);
  }

  // Rooms ---------------------------------------------------------------------

  Future<LiveRoom> _detail(String roomId, {bool roomEntry = false}) async {
    final id = roomId.trim();
    if (!_roomIdPattern.hasMatch(id)) throw NotFound(_site, 'room id "$id" is not a SOOP streamer id');
    final response = await _player(id, type: 'live');
    return SoopApi.roomDetail(
      response.text,
      requestedId: id,
      now: _now(),
      cookie: _cookie(),
      withDanmaku: roomEntry,
      roomEntry: roomEntry,
      status: response.status,
    );
  }

  /// The room with its broadcast and danmaku arguments. A streamer who is
  /// not broadcasting (or blocked) is `StreamUnavailable` here: 3.x's page
  /// reported a failed load for them, while its refresh said offline. An
  /// age-restricted broadcast without an adult-verified cookie is
  /// `NeedsLogin`.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, roomEntry: true);

  /// Follow-card refresh: the same answer without danmaku arguments.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The same answer as the refresh; it holds everything the recorder's
  /// streams need.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// Qualities of the broadcast [detail] carries (a room without one, like
  /// a list card, asks the player API first).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    final qualities = SoopApi.qualities((await _broadcast(detail, fresh: false)).presets);
    if (qualities.isEmpty) throw StreamUnavailable(_site, 'VIEWPRESET: no quality for ${detail.roomId}');
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The line of [quality] for the broadcast [detail] carries.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => await _resolve(detail.roomId.trim(), quality, await _broadcast(detail, fresh: false));

  /// Recovery asks the player API again: a new broadcast has a new number,
  /// and the old one's playlist and key are gone.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => await _resolve(detail.roomId.trim(), quality, await _broadcast(detail, fresh: true));

  /// The broadcast [detail] carries, or (when it has none, or [fresh]) the
  /// player API's; a room that is not broadcasting has none
  /// (`StreamUnavailable`), an age-restricted one needs a login.
  Future<SoopRoomData> _broadcast(LiveRoom detail, {required bool fresh}) async {
    if (detail.data case final SoopRoomData data when !fresh) return data;
    final room = await _detail(detail.roomId);
    final data = room.data;
    if (!room.isLiveNow || data is! SoopRoomData) {
      throw StreamUnavailable(_site, 'player_live_api: ${detail.roomId} is ${room.effectiveLiveStatus.name}');
    }
    return data;
  }

  /// 3.x's order: the playlist assigned for the preset, then its key.
  Future<LivePlayUrlResolution> _resolve(String roomId, LivePlayQuality quality, SoopRoomData data) async {
    if (data.bno.isEmpty || data.rmd.isEmpty) throw const ApiChanged(_site, 'player_live_api: no BNO or RMD');
    final name = '${quality.selectionId}';
    final assign = await _get(SoopApi.assignUrl(rmd: data.rmd, cdn: data.cdn, bno: data.bno, quality: name));
    final playlist = SoopApi.assignedPlaylist(assign.text, status: assign.status);
    final key = await _player(roomId, type: 'aid', bno: data.bno, quality: name);
    return SoopApi.resolution(
      playlist: playlist,
      aid: SoopApi.aid(key.text, status: key.status, password: data.password),
      roomId: roomId,
      quality: name,
      cdn: data.cdn,
      codec: data.codecOf(name),
      cookie: _cookie(),
    );
  }

  // Links ---------------------------------------------------------------------

  /// A streamer page on a SOOP host: the first path segment
  /// (`play.sooplive.co.kr/{id}/{broadcast}`, `ch.sooplive.co.kr/{id}`,
  /// `www.sooplive.com/{id}`), or the one after `station`
  /// (`www.sooplive.co.kr/station/{id}`, which 3.x read as the streamer
  /// "station"). Ids are lower case, as the platform writes them. Search,
  /// VOD and other pages are not rooms.
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return null;
    final host = uri.host.toLowerCase();
    if (!_hosts.any((root) => RoomPaths.hostIs(host, root))) return null;
    var segments = RoomPaths.segments(uri);
    if (segments.isNotEmpty && segments.first.toLowerCase() == 'station') segments = segments.sublist(1);
    if (segments.isEmpty) return null;
    final id = segments.first.trim().toLowerCase();
    if (!RoomPaths.isRoomIdentifier(id, _roomIdPattern) || _pages.contains(id) || id == 'station') return null;
    return id;
  }
}
