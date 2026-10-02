import 'dart:async';

import 'package:live_core/src/json.dart';
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
/// Every request is anonymous: 3.x had no CC account or cookie. Lists,
/// search and room details are 3.x's: the category feeds, `activitylives`
/// then `live/channel`. Where 3.x had nothing the fixes step in: an anchor
/// without a live channel is offline (room entry reads its room page, a
/// follow refresh asks whether the id exists, 9-7). With the approved
/// upgrades (docs/specs/UPGRADES.md) the catalog is the mobile site's (with 3.x's
/// official entries from the Dashen configuration, 9-4) and the qualities
/// are `video_play_url`'s real tiers (9-1), 3.x's redirect playlist being
/// the fallback. Lists send no more requests than 3.x. Failures are
/// `SiteError`s; nothing is disguised as an offline room.
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

  /// How long the `video_play_url` answer that listed a room's qualities
  /// stands in for the request of its own tier (the first play after
  /// entering a room), once. Its URLs admit new connections for 300 s.
  static const Duration qualityAnswerReuse = Duration(seconds: 30);

  /// The limit of a follow refresh's existence check (9-7); past it the
  /// anchor stays marked offline.
  static const Duration existenceTimeout = Duration(seconds: 8);

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;

  /// The last qualities answer of each room, until its tier is played.
  final Map<String, _PlayAnswer> _qualityAnswers = {};

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

  /// The mobile site's catalog (9-4): `gamecategory?catetype=0` names the
  /// categories (网游, 手游, 竞技, 综艺), then one request per category lists
  /// its areas, together; any of them failing fails the catalog (3.x's
  /// all-or-nothing). Categories without areas are left out. After them,
  /// 3.x's "官方房间/专题" from the Dashen registry and configuration,
  /// requested beside the first one, when they can be read; without them
  /// the catalog is still shown. 3.x sent 2 requests; this sends 1 + one
  /// per category (4 today) + 2.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    final [categories, official] = await Future.wait<List<Object>>([_mobileCategories(), _officialAreas()]);
    return [
      ...categories.cast<LiveCategory>(),
      if (official.isNotEmpty)
        LiveCategory(id: 'official', name: CcApi.officialLabel, children: official.cast<LiveArea>()),
    ];
  }

  Future<List<LiveCategory>> _mobileCategories() async {
    Future<LiveResponse> type(String id) =>
        _get(Uri.https('api.cc.163.com', '/v1/wapcc/gamecategory', {'catetype': id}));
    final all = await type('0');
    final types = CcApi.categoryTypes(all.text, status: all.status);
    final answers = await Future.wait([for (final category in types) type(category.id)]);
    return [
      for (final (index, (:id, :name)) in types.indexed)
        if (CcApi.categoryAreas(answers[index].text, id: id, name: name, status: answers[index].status) case final areas
            when areas.isNotEmpty)
          LiveCategory(id: id, name: name, children: areas),
    ];
  }

  /// 3.x's official entries ([CcApi.officialAreas]), or none when the
  /// Dashen requests fail or their answers cannot be read.
  Future<List<LiveArea>> _officialAreas() async {
    try {
      final [games, config] = await Future.wait([
        _send(
          LiveRequest(
            site: _site,
            url: Uri.https('inf.ds.163.com', '/v1/web/game-center/basic/base-info-list/by-type', {
              'gameType': 'NETEASE',
            }),
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
      return CcApi.officialAreas(games.text, config.text, gamesStatus: games.status, configStatus: config.status);
    } on SiteError {
      return const [];
    }
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
  /// broadcasting; 3.x failed there. On room entry the room page fills the
  /// room and tells an unknown id (`NotFound`). A follow refresh of an
  /// anchor without a channel asks [_anchorExists] (9-7); recordings and
  /// status checks only mark the room offline. A non-numeric id is
  /// `NotFound` without a request.
  Future<LiveRoom> _detail(String roomId, {required _Depth depth}) async {
    final ccid = roomId.trim();
    if (!CcApi.ccidPattern.hasMatch(ccid)) throw NotFound(_site, 'room id $ccid is not a ccid');
    final lives = await _get(Uri.https('api.cc.163.com', '/v1/activitylives/anchor/lives', {'anchor_ccid': ccid}));
    final channel = CcApi.liveChannel(lives.text, ccid: ccid, status: lives.status);
    if (channel != null) {
      final response = await _get(Uri.https('cc.163.com', '/live/channel/', {'channelids': channel}));
      final room = CcApi.channelRoom(response.text, ccid: ccid, status: response.status);
      if (room != null) return room;
    }
    if (depth == _Depth.entry) {
      final page = await _get(
        Uri.https('cc.163.com', '/$ccid/', {'open': 'blizzardtv', 'from': '8382', 'platform': 'ds'}),
      );
      return CcApi.pageRoom(page.text, ccid: ccid, status: page.status);
    }
    // A channel that ended in between belongs to an existing anchor.
    if (depth == _Depth.refresh && channel == null && !await _anchorExists(ccid)) {
      throw NotFound(_site, 'no CC account $ccid');
    }
    return CcApi.offlineRoom(ccid);
  }

  /// Whether [ccid] is an account (9-7): one small request
  /// ([CcApi.anchorExists]; about 2.5 KB, 81 bytes for an unknown id, where
  /// the room page is about 110 KB). Only the platform's "no such ccid" is
  /// false: a failed, slow or unreadable answer leaves the anchor marked
  /// offline, as before. A cancellation propagates.
  Future<bool> _anchorExists(String ccid) async {
    try {
      final response = await _send(
        LiveRequest(
          site: _site,
          url: Uri.https('api.cc.163.com', '/v1/wapcc/recommendbyccid', {'ccid': ccid}),
          headers: _headers,
          timeout: existenceTimeout,
        ),
      );
      return CcApi.anchorExists(response.text, status: response.status);
    } on SiteError {
      return true;
    }
  }

  /// The room, with its tier list when on air. CC has no danmaku (3.x
  /// neither), so there are no danmaku arguments.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, depth: _Depth.entry);

  /// Follow-card refresh: 3.x's requests. An anchor without a live channel
  /// is offline, the stored card keeping everything else, unless CC says
  /// the id is no account: `NotFound` (9-7, one request more).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, depth: _Depth.refresh);

  /// A room on air carries its tier list; anything else is offline.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, depth: _Depth.status);

  /// Whether the room is live (3.x always answered true; nothing called it).
  /// A "【重播】" rebroadcast is a replay, not live.
  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId, depth: _Depth.status)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// The room's real tiers from `video_play_url` (9-1; [CcApi.qualities]):
  /// one request, whose answer also stands in for the first play of its
  /// selected tier (see [qualityAnswerReuse]). An anchor who is not
  /// broadcasting is `StreamUnavailable`. When the answer fails otherwise
  /// or cannot be read and the room carries its tier list, 3.x's qualities
  /// are the fallback ([CcApi.legacyQualities], no request).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    try {
      final answer = await _play(detail.roomId);
      final qualities = CcApi.qualities(answer.data);
      _qualityAnswers
        ..remove(detail.roomId.trim())
        ..[detail.roomId.trim()] = answer;
      if (_qualityAnswers.length > 8) _qualityAnswers.remove(_qualityAnswers.keys.first);
      return qualities;
    } on StreamUnavailable {
      rethrow;
    } on SiteError {
      if (detail.data case final CcRoomData data) {
        final qualities = CcApi.legacyQualities(data);
        if (qualities.isNotEmpty) return qualities;
      }
      rethrow;
    }
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// A `video_play_url` quality gets fresh lines every time (a URL admits
  /// new connections for 300 seconds, so renewal and recovery ask again):
  /// the answer to `vbrname={code}`, then one request per CDN of `cdn_list`
  /// it left out, together; a failing CDN request leaves the other lines.
  /// Right after [getPlayQualities], its answer serves the tier it selected
  /// instead of the first request (once, within [qualityAnswerReuse]).
  ///
  /// A 3.x quality (the fallback) plays its own URLs, as 3.x did, without
  /// a request.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    if (quality.data is List) {
      final resolution = CcApi.legacyResolution(quality, roomId: detail.roomId);
      if (!resolution.hasSources) throw StreamUnavailable(_site, 'quality ${quality.id} has no URL');
      return resolution;
    }
    final code = (quality.data ?? quality.id)?.toString();
    final first = _takeQualityAnswer(detail.roomId, code) ?? await _play(detail.roomId, quality: code);
    final others = await Future.wait([
      for (final cdn in CcApi.uncoveredCdns(first.data)) _otherCdn(detail.roomId, quality: code, cdn: cdn),
    ]);
    return CcApi.resolution([first, ...others.nonNulls], roomId: detail.roomId);
  }

  /// The qualities answer of [roomId], taken (every call drops it), when it
  /// is recent and selected [code].
  _PlayAnswer? _takeQualityAnswer(String roomId, String? code) {
    final answer = _qualityAnswers.remove(roomId.trim());
    if (answer == null || code == null || jsonString(answer.data['vbrname_sel']) != code) return null;
    final age = _now().difference(answer.issuedAt);
    return age.isNegative || age > qualityAnswerReuse ? null : answer;
  }

  Future<_PlayAnswer?> _otherCdn(String roomId, {required String? quality, required String cdn}) async {
    try {
      return await _play(roomId, quality: quality, cdn: cdn);
    } on SiteError {
      return null;
    }
  }

  /// `vapi.cc.163.com/video_play_url/{ccid}` as the website's h5 player asks
  /// for it (https URLs), at [quality] and [cdn] when given.
  Future<_PlayAnswer> _play(String roomId, {String? quality, String? cdn}) async {
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

/// A `video_play_url` answer and when it arrived (its leases count from
/// there).
typedef _PlayAnswer = ({Map<String, dynamic> data, DateTime issuedAt});

/// How much of a room [CcSite._detail] reads when the anchor has no live
/// channel.
enum _Depth {
  /// Room entry: the room page, which also tells an unknown id.
  entry,

  /// Follow refresh: the existence check (9-7).
  refresh,

  /// Recording and status checks: nothing more.
  status,
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
