import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/twitcasting/twitcasting_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'twitcasting';

/// Where the pages and `streamserver.php` are answered.
const _host = 'twitcasting.tv';

/// The TwitCasting adapter (3.x's `TwitcastingSite`; parsing in
/// [TwitcastingApi]).
///
/// Every request is anonymous (3.x had no TwitCasting account) and goes as
/// `twitcasting`, so the app routes the platform through its proxy setting;
/// each carries 3.x's headers. The catalog is the homepage's tabs, lists are
/// the one `top/category` window, search is the website's text search, a
/// room is its channel page plus `streamserver.php`, and a stream is the
/// tier playlist that answer names. Room ids stay as the user asked for
/// them; requests use the lower-case channel. Failures are `SiteError`s;
/// nothing is disguised as an offline room.
final class TwitcastingSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LiveCancellableSearch,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter.
  new(this.http);

  /// Transport.
  final LiveHttp http;

  @override
  String get id => _site;

  @override
  String get name => 'TwitCasting';

  // Requests ------------------------------------------------------------------

  /// GETs [url] with 3.x's headers. A cancelled [cancel] sends nothing, and
  /// an answer that arrives after it is dropped (3.x's `read`).
  Future<LiveResponse> _get(Uri url, {bool followRedirects = true, CancelToken? cancel}) async {
    _checkCancelled(cancel);
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(
          site: _site,
          url: url,
          headers: TwitcastingApi.headers,
          followRedirects: followRedirects,
          cancel: cancel,
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    _checkCancelled(cancel);
    return response;
  }

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  // Catalog and lists ---------------------------------------------------------

  /// One category ("TwitCasting") whose areas are the homepage's tabs; only
  /// page 1 has it (3.x).
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1) return const [];
    final response = await _get(Uri.https(_host, '/'));
    return TwitcastingApi.categories(response.text, status: response.status);
  }

  /// The whole site's window (`top/category` without an id); see
  /// [getCategoryRooms] for the paging.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) =>
      _directory('', page: page, pageSize: pageSize);

  /// The window of a homepage tab. The site answers one window of 60
  /// broadcasts; it is asked for whole every time and page [page] of
  /// [pageSize] (1–60) is cut from it, so a page past it is empty without a
  /// request. 3.x's popular and area pages ask for page 1 of 60 and page it
  /// themselves. Another platform's area, a key that is not a tab key or a
  /// page out of range is a caller error (`ArgumentError`) and sends
  /// nothing, as in 3.x.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    if (category.platform != _site ||
        category.areaType != 'directory' ||
        !TwitcastingApi.areaIdPattern.hasMatch(category.areaId)) {
      throw ArgumentError.value(category.areaId, 'category', 'not a TwitCasting tab');
    }
    return await _directory(category.areaId, page: page, pageSize: pageSize);
  }

  Future<List<LiveRoom>> _directory(String category, {required int page, required int pageSize}) async {
    if (page < 1 || page > 10000 || pageSize < 1 || pageSize > TwitcastingApi.directoryWindow) {
      throw ArgumentError('Invalid TwitCasting page $page of $pageSize');
    }
    final offset = (page - 1) * pageSize;
    if (offset >= TwitcastingApi.directoryWindow) return const [];
    final response = await _get(
      Uri.https('frontendapi.twitcasting.tv', '/top/category', {
        'id': category,
        'count': '${TwitcastingApi.directoryWindow}',
      }),
    );
    return TwitcastingApi.directory(response.text, offset: offset, pageSize: pageSize, status: response.status);
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Live broadcasts matching [keyword] (3.x): the search page holds at
  /// most 50 and is asked for again for each page of [pageSize] (1–50); a
  /// page past 50 is empty without a request. A channel link finds that
  /// channel, live or not, on page 1 (an unknown one finds nothing); other
  /// TwitCasting links find nothing. A blank keyword gives nothing without a
  /// request; a page out of range or a keyword over 100 characters is a
  /// caller error (`ArgumentError`), as in 3.x.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final query = keyword.trim();
    if (page < 1 || page > 10000 || pageSize < 1 || pageSize > TwitcastingApi.searchWindow || query.length > 100) {
      throw ArgumentError('Invalid TwitCasting search: page $page of $pageSize, ${query.length} characters');
    }
    if (query.isEmpty || (page - 1) * pageSize >= TwitcastingApi.searchWindow) return const [];
    final link = Uri.tryParse(query);
    if (link != null && TwitcastingApi.hosts.contains(link.host.toLowerCase())) {
      final channel = TwitcastingApi.channelFromUri(link);
      if (channel == null || page != 1) return const [];
      try {
        return [await _detail(channel, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    final response = await _get(
      Uri(
        scheme: 'https',
        host: 'search.twitcasting.tv',
        pathSegments: ['search', 'text', query],
        queryParameters: {'hl': 'en'},
      ),
      cancel: cancel,
    );
    return TwitcastingApi.searchRooms(response.text, page: page, pageSize: pageSize, status: response.status);
  }

  // Rooms ---------------------------------------------------------------------

  /// The room of [roomId] (3.x's two requests): the channel page (not
  /// followed when it redirects: an unknown channel is sent home), then
  /// `streamserver.php` for the state and the broadcast. An id that is not
  /// a channel is `NotFound` without a request.
  Future<LiveRoom> _detail(String roomId, {CancelToken? cancel}) async {
    final requested = roomId.trim();
    final channel = TwitcastingApi.channelName(requested);
    if (channel == null) throw NotFound(_site, 'room id "$requested" is not a TwitCasting channel');
    final page = await _get(Uri.https(_host, '/$channel'), followRedirects: false, cancel: cancel);
    final room = TwitcastingApi.channelPage(page.text, roomId: requested, channel: channel, status: page.status);
    return TwitcastingApi.roomDetail(room, await _stream(channel, cancel: cancel));
  }

  Future<TwitcastingRoomData> _stream(String channel, {CancelToken? cancel}) async {
    final response = await _get(
      Uri.https(_host, '/streamserver.php', {'target': channel, 'mode': 'client', 'player': 'pc_web'}),
      cancel: cancel,
    );
    return TwitcastingApi.streamServer(response.text, status: response.status);
  }

  /// The room with its broadcast. TwitCasting has no danmaku in 3.x, so
  /// there are no danmaku arguments; the broadcast id is in the room's
  /// [TwitcastingRoomData].
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  /// Follow-card refresh: 3.x's two requests (the page refreshes the title,
  /// name and pictures).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The same answer: it holds everything the recorder's streams need.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// 3.x's `HLS high`, `HLS medium`, `HLS low` from the broadcast [detail]
  /// carries, without a request; a room without one (a list card) asks
  /// `streamserver.php`. A room that is not broadcasting has none
  /// (`StreamUnavailable`, 3.x gave an empty list).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      TwitcastingApi.qualities(await _broadcast(detail, fresh: false));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The playlist of [quality] in the broadcast [detail] carries.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => TwitcastingApi.resolution(await _broadcast(detail, fresh: false), quality);

  /// Recovery asks `streamserver.php` again (3.x read the whole room again):
  /// a channel that went live again has a new broadcast and new playlists.
  /// The tier asked for is kept, never silently lowered: a tier the new
  /// broadcast lacks is `StreamUnavailable`.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => TwitcastingApi.resolution(await _broadcast(detail, fresh: true), quality);

  /// The broadcast [detail] carries or, when it has none (or [fresh]), the
  /// one `streamserver.php` reports now. A room known to be offline has none
  /// without a request (REG-TWITCASTING-001).
  Future<TwitcastingRoomData> _broadcast(LiveRoom detail, {required bool fresh}) async {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a TwitCasting room');
    if (!fresh) {
      if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '${detail.roomId} is offline');
      if (detail.data case final TwitcastingRoomData data) return data;
    }
    final channel = TwitcastingApi.channelName(detail.roomId);
    if (channel == null) throw StreamUnavailable(_site, 'room id "${detail.roomId}" is not a TwitCasting channel');
    return await _stream(channel);
  }

  // Links ---------------------------------------------------------------------

  /// A channel page `twitcasting.tv/{id}` (3.x): ids are lower case, with
  /// their `c:`, `g:`, `f:` or `ig:` prefix. Movie links name one old
  /// broadcast and are not rooms (REG-TWITCASTING-003).
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    return uri == null ? null : TwitcastingApi.channelFromUri(uri);
  }
}
