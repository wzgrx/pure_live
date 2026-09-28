import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/cc/cc_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'cc';

/// Headers of the CC API and page requests.
const Map<String, String> _headers = {'user-agent': CcApi.userAgent, 'referer': '${CcApi.origin}/'};

/// Headers of the Dashen catalog requests (3.x's `getCategores`).
const Map<String, String> _dashenHeaders = {
  'user-agent': CcApi.userAgent,
  'referer': 'https://ds.163.com/glive/',
  'origin': 'https://ds.163.com',
};

/// The NetEase CC adapter (3.x's `CCSite`; parsing in [CcApi]).
///
/// Every request is anonymous: 3.x had no CC account or cookie. The catalog,
/// lists, search, room details and streams are 3.x's: the Dashen live
/// configuration, the category feeds, `activitylives` then `live/channel`,
/// and the channel's tiers on its redirect playlist. Where 3.x had nothing
/// the fixes step in: an anchor without a live channel is offline (room
/// entry reads its room page, which also tells an unknown id), and a room
/// without a tier list plays through `video_play_url`. Follow refreshes and
/// lists send no more requests than 3.x. Failures are `SiteError`s; nothing
/// is disguised as an offline room.
final class CcSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LiveSiteCategoryDirectoryProvider,
        LivePlayUrlResolver {
  /// Creates the adapter; [now] (the leases' issue time) is injectable for
  /// tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;

  @override
  String get id => _site;

  @override
  String get name => '网易CC直播';

  @override
  late final LiveSiteDirectoryPager categoryDirectory = _CcCategoryDirectory(this);

  // Requests ------------------------------------------------------------------

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(Uri url, {CancelToken? cancel}) =>
      _send(LiveRequest(site: _site, url: url, headers: _headers, cancel: cancel));

  // Catalog and search --------------------------------------------------------

  /// The Dashen game registry and live configuration, requested together:
  /// the configuration's live entries become the areas of "直播分类" and
  /// "官方房间/专题" (see [CcApi.categories]); either failing fails the
  /// catalog.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    final [games, config] = await Future.wait([
      _send(
        LiveRequest(
          site: _site,
          url: Uri.https('inf.ds.163.com', '/v1/web/game-center/basic/base-info-list/by-type', {'gameType': 'NETEASE'}),
          headers: _dashenHeaders,
        ),
      ),
      _send(
        LiveRequest.json(
          site: _site,
          url: Uri.https('inf-act.ds.163.com', '/v1/act-web/pageConf/commonAppConfig'),
          json: const {'id': CcApi.catalogConfigurationId},
          headers: _dashenHeaders,
        ),
      ),
    ]);
    return CcApi.categories(games.text, config.text, gamesStatus: games.status, configStatus: config.status);
  }

  /// Rooms of a live area: `start` = (page − 1) × [pageSize]. An official
  /// entry, another platform's area or a page out of 1–100000 × 1–1000 is a
  /// caller error (`ArgumentError`) and sends nothing, as in 3.x.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) =>
      _categoryRooms(category, page: page, pageSize: pageSize);

  Future<List<LiveRoom>> _categoryRooms(
    LiveArea category, {
    required int page,
    required int pageSize,
    CancelToken? cancel,
  }) async {
    if (!CcApi.isListableArea(category) || page < 1 || page > 100000 || pageSize < 1 || pageSize > 1000) {
      throw ArgumentError('Invalid CC category or pagination');
    }
    final game = category.areaId.trim();
    final response = await _get(
      Uri.https('cc.163.com', '/api/category/$game/', {
        'format': 'json',
        'tag_id': '0',
        'start': '${(page - 1) * pageSize}',
        'size': '$pageSize',
      }),
      cancel: cancel,
    );
    return CcApi.categoryRooms(response.text, gametype: game, status: response.status);
  }

  /// Every live room, [pageSize] a page (the popular page asks for 100).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    final size = pageSize < 1 ? 1 : pageSize;
    final response = await _get(
      Uri.https('cc.163.com', '/api/category/live/', {
        'format': 'json',
        'start': '${((page < 1 ? 1 : page) - 1) * size}',
        'size': '$size',
      }),
    );
    return CcApi.recommendRooms(response.text, status: response.status);
  }

  /// Streamers matching [keyword], live or not; [pageSize] is sent, limited
  /// to 1–50. The path ends with a slash (without it the site answers 301).
  /// A blank keyword gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final response = await _get(
      Uri.https('cc.163.com', '/search/anchor/', {
        'query': text,
        'size': '${pageSize.clamp(1, 50)}',
        'page': '${page < 1 ? 1 : page}',
      }),
    );
    return CcApi.searchRooms(response.text, status: response.status);
  }

  /// The streamers of [searchRooms] (3.x did the same).
  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async => [
    for (final room in await searchRooms(keyword, page: page, pageSize: pageSize))
      LiveAnchorItem(roomId: room.roomId, avatar: room.avatar, userName: room.nick, liveStatus: room.isLiveNow),
  ];

  // Rooms ---------------------------------------------------------------------

  /// The room of [roomId], as the user asked for it (3.x's two requests):
  /// 1. `activitylives` gives the channel the anchor broadcasts in;
  /// 2. with one, `live/channel` gives the live room.
  ///
  /// Without a channel (or when it ended in between) the anchor is not
  /// broadcasting; 3.x failed there. On room entry ([enter]) the room page
  /// fills the room and tells an unknown id (`NotFound`); otherwise the room
  /// is only marked offline, with no request more than 3.x made. A
  /// non-numeric id is `NotFound` without a request.
  Future<LiveRoom> _detail(String roomId, {required bool enter}) async {
    final ccid = roomId.trim();
    if (!CcApi.ccidPattern.hasMatch(ccid)) throw NotFound(_site, 'room id $ccid is not a ccid');
    final lives = await _get(Uri.https('api.cc.163.com', '/v1/activitylives/anchor/lives', {'anchor_ccid': ccid}));
    final channel = CcApi.liveChannel(lives.text, ccid: ccid, status: lives.status);
    if (channel != null) {
      final response = await _get(Uri.https('cc.163.com', '/live/channel/', {'channelids': channel}));
      final room = CcApi.channelRoom(response.text, ccid: ccid, status: response.status);
      if (room != null) return room;
    }
    if (!enter) return CcApi.offlineRoom(ccid);
    final page = await _get(
      Uri.https('cc.163.com', '/$ccid/', {'open': 'blizzardtv', 'from': '8382', 'platform': 'ds'}),
    );
    return CcApi.pageRoom(page.text, ccid: ccid, status: page.status);
  }

  /// The room, with its tier list when live. CC has no danmaku (3.x
  /// neither), so there are no danmaku arguments.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, enter: true);

  /// Follow-card refresh: 3.x's requests; an anchor without a live channel
  /// is offline, the stored card keeping everything else.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, enter: false);

  /// As the refresh: a live room carries its tier list, anything else is
  /// offline.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, enter: false);

  /// Whether the room is live (3.x always answered true; nothing called it).
  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId, enter: false)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities from the room's tier list ([CcApi.legacyQualities]):
  /// no request. A room without one (not live, or a card without a detail)
  /// asks `video_play_url` for its tiers instead; an anchor who is not
  /// broadcasting is `StreamUnavailable` there.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    if (detail.data case final CcRoomData data) {
      final qualities = CcApi.legacyQualities(data);
      if (qualities.isNotEmpty) return qualities;
    }
    return CcApi.qualities((await _play(detail.roomId)).data);
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// A 3.x quality plays its own URLs, as 3.x did, without a request. A
  /// `video_play_url` quality (the fallback) gets fresh lines every time (a
  /// URL admits new connections for 300 seconds, so renewal and recovery
  /// ask again): the answer to `vbrname={code}`, then one request per CDN of
  /// `cdn_list` it left out, together; a failing CDN request leaves the
  /// other lines.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    if (quality.data is List) {
      final resolution = CcApi.legacyResolution(quality, roomId: detail.roomId);
      if (!resolution.hasSources) throw StreamUnavailable(_site, 'quality ${quality.id} has no URL');
      return resolution;
    }
    final code = (quality.data ?? quality.id)?.toString();
    final first = await _play(detail.roomId, quality: code);
    final others = await Future.wait([
      for (final cdn in CcApi.uncoveredCdns(first.data)) _otherCdn(detail.roomId, quality: code, cdn: cdn),
    ]);
    return CcApi.resolution([first, ...others.nonNulls], roomId: detail.roomId);
  }

  Future<({Map<String, dynamic> data, DateTime issuedAt})?> _otherCdn(
    String roomId, {
    required String? quality,
    required String cdn,
  }) async {
    try {
      return await _play(roomId, quality: quality, cdn: cdn);
    } on SiteError {
      return null;
    }
  }

  /// `vapi.cc.163.com/video_play_url/{ccid}` as the website's h5 player asks
  /// for it (https URLs), at [quality] and [cdn] when given.
  Future<({Map<String, dynamic> data, DateTime issuedAt})> _play(String roomId, {String? quality, String? cdn}) async {
    final ccid = roomId.trim();
    if (!CcApi.ccidPattern.hasMatch(ccid)) throw StreamUnavailable(_site, 'room id $ccid is not a ccid');
    final response = await _get(
      Uri.https('vapi.cc.163.com', '/video_play_url/$ccid', {
        'src': 'webcc_h5',
        'vbrmode': '1',
        'use_new_vbrmap': '1',
        'secure': '1',
        'vbrname': ?quality,
        'cdn': ?cdn,
      }),
    );
    final issuedAt = _now();
    return (data: CcApi.playData(response.text, status: response.status), issuedAt: issuedAt);
  }

  // Links ---------------------------------------------------------------------

  /// A room of `cc.163.com/{ccid}` (3.x), and the two forms the site now
  /// shares: the mobile page `h5.cc.163.com/cc/{ccid}` and the Dashen player
  /// `ds.163.com/glive/?ccid={ccid}` (where `cc.163.com/{ccid}/` redirects).
  /// Only numeric ids are rooms: 3.x's manual-link rule also took any word
  /// (`cc.163.com/n/…` pages became room "n").
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) return null;
    final host = uri.host.toLowerCase();
    final segments = RoomPaths.segments(uri);
    return switch (host) {
      'cc.163.com' when segments.isNotEmpty => _roomNumber(segments.first),
      'h5.cc.163.com' when segments.length >= 2 && segments.first == 'cc' => _roomNumber(segments[1]),
      'ds.163.com' when segments.firstOrNull == 'glive' => _roomNumber(uri.queryParameters['ccid'] ?? ''),
      _ => null,
    };
  }

  /// A positive decimal ccid without leading zeros, or null.
  static String? _roomNumber(String text) {
    final value = text.trim();
    if (!RegExp(r'^\d{1,16}$').hasMatch(value)) return null;
    final number = int.parse(value);
    return number > 0 ? '$number' : null;
  }
}

/// 3.x's `_CCCategoryDirectory`: pages of a fixed 30 rooms, so offsets never
/// depend on the visible page size; a full page means there may be more.
final class _CcCategoryDirectory implements LiveSiteDirectoryPager {
  new(this.site);

  final CcSite site;

  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (category == null) throw ArgumentError('CC category is required');
    final rooms = await site._categoryRooms(category, page: page, pageSize: CcApi.directoryPageSize, cancel: cancel);
    if (rooms.length > CcApi.directoryPageSize) {
      throw ApiChanged(_site, 'category ${category.areaId}: ${rooms.length} rooms for ${CcApi.directoryPageSize}');
    }
    return LiveDirectoryPage(rooms: rooms, page: page, hasMore: rooms.length == CcApi.directoryPageSize);
  }
}
