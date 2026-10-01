import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/kick/kick_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'kick';

/// The Kick adapter (pure_live_TV's `KickSite`, e1cca224; parsing in
/// [KickApi]).
///
/// Anonymous and read-only. Kick's API host sits behind a Cloudflare check
/// that refuses dart:io's TLS handshake (HTTP 403 "Request blocked by
/// security policy."), so its requests go through [apiHttp] (the app passes
/// Android's system TLS, `AndroidNativeHttp`); the IVS master playlist goes
/// through [http]. Room ids are channel slugs in lower case (Kick finds a
/// channel in any case; `SiteIds.caseInsensitiveRoomIds`).
///
/// - Catalog: Kick's top-level categories, each with its 32 most watched
///   subcategories (one request for the list, one per category at once).
/// - Lists: `stream/livestreams` by viewers, 30 a page; a subcategory area
///   adds its slug.
/// - Search: one page of channels (live or not), then live broadcasts whose
///   tags match.
/// - Room entry: the channel answer and, when live, its signed master
///   playlist ([KickRoomData]) and the chat's [KickDanmakuArgs]; follow
///   refreshes read the channel answer only.
final class KickSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LiveSiteDirectoryPager,
        LiveCancellableSearch {
  /// Creates the adapter. Requests to kick.com go through [apiHttp] (by
  /// default [http]); media requests through [http].
  new(this.http, {LiveHttp? apiHttp}) : apiHttp = apiHttp ?? http;

  /// Transport of the media requests (the master playlist).
  final LiveHttp http;

  /// Transport of the kick.com API requests.
  final LiveHttp apiHttp;

  @override
  String get id => _site;

  @override
  String get name => 'Kick';

  // Requests ------------------------------------------------------------------

  Future<LiveResponse> _send(LiveHttp transport, Uri url, Map<String, String> headers, CancelToken? cancel) async {
    try {
      return await transport.send(LiveRequest(site: _site, url: url, headers: headers, cancel: cancel));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _api(String path, [Map<String, String>? query, CancelToken? cancel]) =>
      _send(apiHttp, Uri.https(KickApi.apiHost, path, query), KickApi.headers, cancel);

  // Catalog -------------------------------------------------------------------

  /// Kick's top-level categories, each with its most watched subcategories;
  /// only page 1 has them. A category whose subcategories fail is left out;
  /// when all fail, the first failure is thrown.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1) return const [];
    final response = await _api('/api/v1/categories');
    final parents = KickApi.mainCategories(response.text, status: response.status);
    final results = await Future.wait([
      for (final parent in parents)
        _subcategories(parent).then<Object>((areas) => areas, onError: (Object error) => error),
    ]);
    final categories = <LiveCategory>[];
    Object? failure;
    for (final (index, result) in results.indexed) {
      if (result is List<LiveArea>) {
        if (result.isNotEmpty) {
          categories.add(LiveCategory(id: parents[index].slug, name: parents[index].name, children: result));
        }
      } else {
        failure ??= result;
      }
    }
    if (categories.isEmpty && failure != null) {
      if (failure is SiteError) throw failure;
      throw NetworkFailure(_site, '$failure');
    }
    return categories;
  }

  Future<List<LiveArea>> _subcategories(KickMainCategory parent) async {
    final response = await _api('/api/v1/subcategories', {
      'category': parent.slug,
      'limit': '${KickApi.subcategoryLimit}',
      'page': '1',
    });
    return KickApi.subcategories(response.text, parent: parent, status: response.status);
  }

  /// Page [page] of [category]'s live broadcasts, or of all of Kick's
  /// (recommendations) when null.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) =>
      _livestreams(page: page, pageSize: KickApi.pageSize, subcategory: _subcategory(category), cancel: cancel);

  /// All live broadcasts by viewers; [pageSize] is sent, limited to 1–30.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await _livestreams(page: page, pageSize: pageSize)).rooms;

  /// [category]'s live broadcasts by viewers; [pageSize] as in
  /// [getRecommendRooms].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      (await _livestreams(page: page, pageSize: pageSize, subcategory: _subcategory(category))).rooms;

  Future<LiveDirectoryPage> _livestreams({
    required int page,
    required int pageSize,
    String? subcategory,
    CancelToken? cancel,
  }) async {
    final number = page < 1 ? 1 : page;
    final size = pageSize.clamp(1, KickApi.pageSize);
    final response = await _api('/stream/livestreams/en', {
      'page': '$number',
      'limit': '$size',
      'sort': 'desc',
      'subcategory': ?subcategory,
    }, cancel);
    return KickApi.directoryPage(
      response.text,
      page: number,
      pageSize: size,
      subcategory: subcategory,
      status: response.status,
    );
  }

  /// The subcategory slug of [area], or null for none; another platform's
  /// area or type is a caller's mistake.
  static String? _subcategory(LiveArea? area) {
    if (area == null) return null;
    final slug = area.areaId.trim();
    if (area.platform != _site ||
        area.areaType != 'subcategory' ||
        !RegExp(r'^[A-Za-z0-9:+_-]{1,100}$').hasMatch(slug)) {
      throw ArgumentError.value(area, 'category', 'not a Kick subcategory');
    }
    return slug;
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Channels matching [keyword] (its first 50 characters), live or not, and
  /// live broadcasts tagged with it. Kick's search has one page: later
  /// pages and a blank keyword give nothing without a request.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final text = keyword.trim();
    if (text.isEmpty || page > 1) return const [];
    final words = text.length > KickApi.maxKeywordLength ? text.substring(0, KickApi.maxKeywordLength) : text;
    final response = await _api('/api/search', {'searched_word': words}, cancel);
    return KickApi.searchRooms(response.text, status: response.status);
  }

  // Rooms ---------------------------------------------------------------------

  Future<KickChannel> _channel(String roomId) async {
    final slug = KickApi.normalizeSlug(roomId);
    if (slug == null) throw NotFound(_site, 'room id "${roomId.trim()}" is not a Kick channel');
    final response = await _api('/api/v2/channels/$slug');
    return KickApi.channel(response.text, requestedSlug: slug, status: response.status);
  }

  /// The channel and, when live, its stream; [entry] adds the danmaku
  /// arguments.
  Future<LiveRoom> _entered(String roomId, {bool entry = false}) async {
    final channel = await _channel(roomId);
    final master = channel.master;
    KickRoomData? data;
    if (master != null) {
      final response = await _send(http, master, KickApi.mediaHeaders(channel.room.roomId), null);
      data = KickApi.roomData(response.text, slug: channel.room.roomId, master: master, status: response.status);
    }
    return channel.room.copyWith(data: data, danmakuData: entry ? KickApi.danmakuArgs(channel) : null);
  }

  /// The room with its stream (when live) and danmaku arguments.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _entered(roomId, entry: true);

  /// Follow-card refresh: the channel answer only, one request.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async => (await _channel(roomId)).room;

  /// Room entry's answer (the stream included), for the recorder.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _entered(roomId);

  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// Qualities of the stream [detail] carries (a room without one, like a
  /// list card, is entered first). A room Kick said is offline or banned has
  /// none (`StreamUnavailable`, without a request).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      (await _stream(detail, fresh: false)).qualities;

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The line of [quality] in the stream [detail] carries; a room without
  /// one is entered first, and the best quality stands in for one the new
  /// master no longer has.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => _resolve(await _stream(detail, fresh: false), quality, best: detail.data is! KickRoomData);

  /// Recovery reads the channel and a fresh master playlist (a new token)
  /// and plays [quality] again, or the best one when it is gone.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => _resolve(await _stream(detail, fresh: true), quality, best: true);

  Future<KickRoomData> _stream(LiveRoom detail, {required bool fresh}) async {
    if (detail.data case final KickRoomData data when !fresh) return data;
    if (!fresh && detail.isExplicitlyOfflineNow) {
      throw StreamUnavailable(_site, '${detail.roomId} is ${detail.effectiveLiveStatus.name}');
    }
    final room = await _entered(detail.roomId);
    if (room.data case final KickRoomData data) return data;
    throw StreamUnavailable(_site, 'channel ${detail.roomId} is ${room.effectiveLiveStatus.name}');
  }

  static LivePlayUrlResolution _resolve(KickRoomData data, LivePlayQuality quality, {required bool best}) {
    final wanted = '${quality.id}';
    final current =
        data.qualities.where((option) => '${option.id}' == wanted).firstOrNull ??
        (best ? data.qualities.firstOrNull : null);
    if (current == null) throw StreamUnavailable(_site, 'master playlist: no quality $wanted');
    return KickApi.resolution(data, current);
  }

  // Links ---------------------------------------------------------------------

  /// A channel page on `kick.com` ([KickApi.slugFromUrl]).
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri == null ? null : KickApi.slugFromUrl(uri);
  }
}
