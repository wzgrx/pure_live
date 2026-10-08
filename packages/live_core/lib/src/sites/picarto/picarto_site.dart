import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/picarto/picarto_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'picarto';

/// The Picarto adapter (3.x's `PicartoSite` and `PicartoApi`; parsing in
/// [PicartoApi]).
///
/// Anonymous: every request goes as `picarto` with [PicartoApi.headers] and
/// no cookie (3.x had no Picarto login). The catalog is one category whose
/// first area is the public directory; lists come from `api/explore` pages
/// of 30, search from channel profiles (offline ones too). Room entry reads
/// the detail and, when live, the HLS master playlist on the edge the load
/// balancer chose (3.x's two requests) and, at the same time, the public
/// API's start of the broadcast; follow refreshes read the detail only.
/// Room ids are the platform's spelling of the channel name, as 3.x stored
/// follows (a room asked for as `thebaker` is `TheBaker`); rooms compare
/// ignoring case (`SiteIds.caseInsensitiveRoomIds`, 11-8). Failures are
/// `SiteError`s; nothing is disguised as an offline room.
final class PicartoSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LiveSiteDirectoryPager,
        LiveCancellableSearch {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => 'Picarto';

  // Requests ------------------------------------------------------------------

  Future<LiveResponse> _get(Uri url, {CancelToken? cancel}) async {
    try {
      return await http.send(LiveRequest(site: _site, url: url, headers: PicartoApi.headers, cancel: cancel));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  // Catalog -------------------------------------------------------------------

  /// One category, "Picarto": the public directory, then the platform's
  /// categories. Only page 1 has it (3.x).
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1) return const [];
    final response = await _get(Uri.https(PicartoApi.apiHost, '/api/languages-categories'));
    return [PicartoApi.catalog(response.text, status: response.status)];
  }

  /// Page [page] of [category]'s live channels, or of the public directory
  /// (recommendations) when [category] is null or that area. 30 a page, as
  /// 3.x's directory pager asked.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async =>
      await _explore(page: page, pageSize: PicartoApi.pageSize, categoryId: _categoryId(category), cancel: cancel);

  /// Live channels by viewers, adult content excluded; [pageSize] is sent,
  /// limited to 1–60.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await _explore(page: page, pageSize: pageSize)).rooms;

  /// Live channels of [category] (the public directory is the
  /// recommendations); [pageSize] as in [getRecommendRooms].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      (await _explore(page: page, pageSize: pageSize, categoryId: _categoryId(category))).rooms;

  /// `api/explore`: 3.x's query (by viewers, `filter_params[adult]=false`;
  /// a category adds an empty language filter and `<id>: true`).
  Future<LiveDirectoryPage> _explore({
    required int page,
    required int pageSize,
    int? categoryId,
    CancelToken? cancel,
  }) async {
    final number = page < 1 ? 1 : page;
    final size = pageSize.clamp(1, PicartoApi.maxPageSize);
    final response = await _get(
      Uri.https(PicartoApi.apiHost, '/api/explore', {
        'first': '$size',
        'page': '$number',
        'filter_params[adult]': 'false',
        'order_by[field]': 'viewers',
        'order_by[order]': 'DESC',
        'type': 'stream',
        if (categoryId != null) 'filter_params[languages]': '',
        if (categoryId != null) 'filter_params[categories]': '$categoryId: true',
      }),
      cancel: cancel,
    );
    return PicartoApi.directoryPage(
      response.text,
      page: number,
      pageSize: size,
      categoryId: categoryId,
      status: response.status,
    );
  }

  /// The category id of [area]: null for the public directory, else a
  /// Picarto `category` area with a canonical positive id. Anything else is
  /// a caller's mistake (3.x refused it before any request).
  static int? _categoryId(LiveArea? area) {
    if (area == null ||
        (area.platform == _site && area.areaType == 'directory' && area.areaId == PicartoApi.publicDirectory.areaId)) {
      return null;
    }
    final id = int.tryParse(area.areaId);
    if (area.platform != _site || area.areaType != 'category' || id == null || id <= 0 || '$id' != area.areaId) {
      throw ArgumentError.value(area, 'category', 'not a Picarto category');
    }
    return id;
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Channel profiles matching [keyword], live and offline; [pageSize] is
  /// sent, limited to 1–60, and the keyword's first 100 characters. A blank
  /// keyword gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final size = pageSize.clamp(1, PicartoApi.maxPageSize);
    final response = await _get(
      Uri.https(PicartoApi.apiHost, '/api/search', {
        'first': '$size',
        'page': '${page < 1 ? 1 : page}',
        'q': text.length > PicartoApi.maxKeywordLength ? text.substring(0, PicartoApi.maxKeywordLength) : text,
        'type': 'searchProfiles',
        'tag_search': 'false',
      }),
      cancel: cancel,
    );
    return PicartoApi.searchRooms(response.text, pageSize: size, status: response.status);
  }

  // Rooms ---------------------------------------------------------------------

  /// `api/channel/detail/<name>`, with the stream fields checked when
  /// [stream]; a room id that is no channel name is `NotFound` without a
  /// request.
  Future<PicartoChannel> _detail(String roomId, {required bool stream}) async {
    final id = roomId.trim();
    if (!PicartoApi.isChannelName(id)) throw NotFound(_site, 'room id "$id" is not a Picarto channel name');
    final response = await _get(Uri.https(PicartoApi.apiHost, '/api/channel/detail/$id'));
    return PicartoApi.roomDetail(response.text, requestedId: id, status: response.status, stream: stream);
  }

  /// The detail and, when live, the master playlist's qualities in
  /// [PicartoRoomData] (3.x's room entry; a private channel has no stream,
  /// 11-9) and the danmaku arguments (no request). [entry] (the room page)
  /// adds, for a live channel, the start of its broadcast, asked for beside
  /// the master playlist (one request more than 3.x; the room stands
  /// without it).
  Future<LiveRoom> _entered(String roomId, {bool entry = false}) async {
    final channel = await _detail(roomId, stream: true);
    final since = entry && channel.room.isLiveNow ? _liveSince(channel.name) : null;
    final master = channel.master;
    PicartoRoomData? data;
    if (master != null) {
      try {
        final response = await _get(master);
        data = PicartoRoomData(
          name: channel.name,
          channelId: channel.channelId,
          master: master,
          qualities: PicartoApi.qualities(response.text, master: master, status: response.status),
          requestedId: channel.requestedId,
        );
      } on Object {
        since?.ignore();
        rethrow;
      }
    }
    return channel.room.copyWith(data: data, danmakuData: PicartoApi.danmakuArgs(channel), startedAt: await since);
  }

  /// The start of [name]'s broadcast on air ([PicartoApi.liveSince]), or
  /// null when the public API fails or does not say. Never completes with
  /// an exception, so it can run beside the master playlist.
  Future<DateTime?> _liveSince(String name) async {
    try {
      final response = await _get(Uri.https(PicartoApi.publicApiHost, '/api/v1/channel/name/$name'));
      return PicartoApi.liveSince(response.text, name: name, status: response.status);
    } on Exception {
      // SiteError, a cancelled TransportFailure: the room stands without it.
      return null;
    }
  }

  /// The room with its stream (when live), the start of its broadcast and
  /// danmaku arguments.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _entered(roomId, entry: true);

  /// Follow-card refresh: the detail only, one request as in 3.x. The
  /// stream fields are not checked (11-2): a live channel whose answer lacks
  /// its edge or stream still refreshes. The detail has no start time, so
  /// `startedAt` stays null (the follow keeps the one room entry found
  /// while the state does not change).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async =>
      (await _detail(roomId, stream: false)).room;

  /// Room entry's answer (the stream and the danmaku arguments included,
  /// for multi-view; E05.4), as 3.x's recorder asked, without the start.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _entered(roomId);

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// Qualities of the stream [detail] carries (a room without one, like a
  /// list card, is entered first). A room the platform said is offline has
  /// none (`StreamUnavailable`, without a request; 3.x listed nothing); a
  /// private channel neither (`StreamUnavailable` naming it private, 11-9).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      (await _stream(detail, fresh: false)).qualities;

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] in the stream [detail] carries. A room without
  /// one is entered first, and when its playlist no longer has [quality]
  /// the best quality is played instead (as in recovery).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => _resolve(await _stream(detail, fresh: false), quality, best: detail.data is! PicartoRoomData);

  /// Recovery reads the detail and the master playlist again: the load
  /// balancer may have moved the stream to another edge (REG-PICARTO-003).
  /// When the streamer changed the profile (720p60 → 1080p60) the playlist
  /// no longer has [quality]: the best quality is played and reported as
  /// applied (11-1; 3.x failed the recovery).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => _resolve(await _stream(detail, fresh: true), quality, best: true);

  /// The stream [detail] carries, or (when it has none, or [fresh]) the one
  /// of a new room entry; a channel that is not live, or private, has none.
  Future<PicartoRoomData> _stream(LiveRoom detail, {required bool fresh}) async {
    if (detail.data case final PicartoRoomData data when !fresh) return data;
    if (!fresh && detail.isExplicitlyOfflineNow) {
      throw StreamUnavailable(_site, '${detail.roomId} is ${detail.effectiveLiveStatus.name}');
    }
    final room = await _entered(detail.roomId);
    final data = room.data;
    if (data is PicartoRoomData) return data;
    if (room.isLiveNow && room.effectiveRestriction == LiveRestriction.private) {
      throw StreamUnavailable(_site, "channel ${room.roomId} is private: it needs the streamer's private key");
    }
    throw StreamUnavailable(_site, 'channel/detail: ${detail.roomId} is ${room.effectiveLiveStatus.name}');
  }

  /// The lines of the quality of [data] that is [quality] (by id: the
  /// profile, whatever the edge). A profile the playlist no longer has is
  /// `StreamUnavailable` (3.x's "quality unavailable"), or with [best] the
  /// playlist's best quality, whose id the resolution reports and which it
  /// names as the quality played instead (11-1,
  /// [LivePlayUrlResolution.appliedQuality]).
  static LivePlayUrlResolution _resolve(PicartoRoomData data, LivePlayQuality quality, {required bool best}) {
    final wanted = '${quality.selectionId}';
    final same = data.qualities.where((option) => '${option.selectionId}' == wanted).firstOrNull;
    final current = same ?? (best ? data.qualities.firstOrNull : null);
    if (current == null) throw StreamUnavailable(_site, 'master playlist: no quality $wanted');
    final resolution = PicartoApi.resolution(current, master: data.master);
    if (same != null) return resolution;
    return LivePlayUrlResolution.lines(
      resolution.lines,
      appliedQualityData: resolution.appliedQualityData,
      appliedQuality: current,
    );
  }

  // Links ---------------------------------------------------------------------

  /// A channel page on `picarto.tv` (3.x's rule, see
  /// [PicartoApi.channelFromUrl]), spelled as in the link; the detail
  /// answers with the platform's spelling, the room id (3.x).
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri == null ? null : PicartoApi.channelFromUrl(uri);
  }
}
