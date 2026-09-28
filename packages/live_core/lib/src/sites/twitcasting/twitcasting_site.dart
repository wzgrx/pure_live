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

/// How long a list or search snapshot serves the pages after the first (the
/// unified paging rule: 20–30 s). The first page always fetches a new one.
const _snapshotLifetime = Duration(seconds: 30);

/// Snapshots kept (the oldest is dropped first).
const _snapshotLimit = 16;

/// One answer of a list (`top/category`) or a search, paged locally: one
/// entry per row, null for a row left out, and when it arrived.
typedef _Snapshot = ({DateTime fetchedAt, List<LiveRoom?> window});

/// The TwitCasting adapter (3.x's `TwitcastingSite`; parsing in
/// [TwitcastingApi]).
///
/// Every request is anonymous (3.x had no TwitCasting account) and goes as
/// `twitcasting`, so the app routes the platform through its proxy setting;
/// each carries 3.x's headers. The catalog is the homepage's tabs, lists are
/// the one `top/category` window, search is the website's text search, a
/// room is its channel page plus `streamserver.php` (a follow refresh is
/// `streamserver.php` alone), and a stream is the tier playlist that answer
/// names. A list or search answer is kept for 30 s and later pages are cut
/// from it. Room ids stay as the user asked for them; requests use the
/// lower-case channel. Failures are `SiteError`s; nothing is disguised as an
/// offline room.
final class TwitcastingSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LiveCancellableSearch,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter; [now] (the lists' start times, the snapshots'
  /// age) is injectable for tests.
  new(this.http, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;

  /// The list and search answers, by `top|<tab>` and `search|<keyword>`.
  final Map<String, _Snapshot> _snapshots = {};

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

  /// The answer [key] for page [page]: page 1 always fetches a new one with
  /// [fetch]; a later page uses the kept one while it is under 30 s old, so
  /// the pages of one browse come from one answer (12-4, the unified paging
  /// rule). A failed fetch keeps nothing.
  Future<List<LiveRoom?>> _snapshot(String key, int page, Future<List<LiveRoom?>> Function() fetch) async {
    final kept = _snapshots[key];
    if (page > 1 && kept != null && _now().difference(kept.fetchedAt) < _snapshotLifetime) return kept.window;
    final window = await fetch();
    _snapshots
      ..remove(key)
      ..[key] = (fetchedAt: _now(), window: window);
    if (_snapshots.length > _snapshotLimit) _snapshots.remove(_snapshots.keys.first);
    return window;
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
  /// broadcasts; page 1 asks for it whole and page [page] of [pageSize]
  /// (1–60) is cut from it as 3.x cut it. A later page is cut from the same
  /// answer while it is under 30 s old (the unified paging rule; 3.x asked
  /// again), and a page past the window is empty without a request. 3.x's
  /// popular and area pages ask for page 1 of 60 and page it themselves.
  /// Another platform's area, a key that is not a tab key or a page out of
  /// range is a caller error (`ArgumentError`) and sends nothing, as in
  /// 3.x.
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
    final window = await _snapshot('top|$category', page, () async {
      final response = await _get(
        Uri.https('frontendapi.twitcasting.tv', '/top/category', {
          'id': category,
          'count': '${TwitcastingApi.directoryWindow}',
        }),
      );
      return TwitcastingApi.directoryRows(response.text, status: response.status, now: _now());
    });
    return TwitcastingApi.slice(window, offset: offset, pageSize: pageSize);
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Live broadcasts matching [keyword], private ones included and marked
  /// (12-5): the search page holds at most 50. Page 1 asks for it and page
  /// [page] of [pageSize] (1–50) is cut from it; a later page is cut from
  /// the same answer while it is under 30 s old (12-4; 3.x asked again for
  /// each page), and a page past 50 is empty without a request. A channel
  /// link finds that channel, live or not, on page 1 (an unknown one finds
  /// nothing); other TwitCasting links find nothing. A blank keyword gives
  /// nothing without a request; a page out of range or a keyword over 100
  /// characters is a caller error (`ArgumentError`), as in 3.x. A cancelled
  /// [cancel] sends nothing and serves nothing.
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
    _checkCancelled(cancel);
    final window = await _snapshot('search|$query', page, () async {
      final response = await _get(
        Uri(
          scheme: 'https',
          host: 'search.twitcasting.tv',
          pathSegments: ['search', 'text', query],
          queryParameters: {'hl': 'en'},
        ),
        cancel: cancel,
      );
      return TwitcastingApi.searchRows(response.text, status: response.status);
    });
    return TwitcastingApi.slice(window, offset: (page - 1) * pageSize, pageSize: pageSize);
  }

  // Rooms ---------------------------------------------------------------------

  /// The room of [roomId] (3.x's two requests): the channel page (not
  /// followed when it redirects: an unknown channel is sent home), then
  /// `streamserver.php` for the state and the broadcast. A page asking for
  /// the secret word asks `streamserver.php` too (3.x stopped there), so a
  /// protected broadcast shows as live. An id that is not a channel is
  /// `NotFound` without a request.
  Future<LiveRoom> _detail(String roomId, {CancelToken? cancel}) async {
    final (:requested, :channel) = _channel(roomId);
    final page = await _get(Uri.https(_host, '/$channel'), followRedirects: false, cancel: cancel);
    final parsed = TwitcastingApi.channelPage(page.text, roomId: requested, channel: channel, status: page.status);
    return TwitcastingApi.roomDetail(parsed, await _stream(channel, cancel: cancel));
  }

  /// [roomId] trimmed, and its lower-case channel; `NotFound` when it is
  /// not one.
  static ({String requested, String channel}) _channel(String roomId) {
    final requested = roomId.trim();
    final channel = TwitcastingApi.channelName(requested);
    if (channel == null) throw NotFound(_site, 'room id "$requested" is not a TwitCasting channel');
    return (requested: requested, channel: channel);
  }

  Future<TwitcastingRoomData> _stream(String channel, {CancelToken? cancel}) async {
    final response = await _get(
      Uri.https(_host, '/streamserver.php', {'target': channel, 'mode': 'client', 'player': 'pc_web'}),
      cancel: cancel,
    );
    return TwitcastingApi.streamServer(response.text, status: response.status);
  }

  /// The room with its broadcast, its telop as the title (12-1) and, when
  /// live, its start time and comment arguments ([TwitcastingDanmakuArgs],
  /// for M5; 3.x had no TwitCasting comments).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  /// Follow-card refresh: `streamserver.php` alone, about 1 KB instead of
  /// the 110 KB channel page (12-2; 3.x read both). The state and the
  /// broadcast are new; the names, pictures and title stay as the follow
  /// stored them until the room is entered.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async {
    final (:requested, :channel) = _channel(roomId);
    return TwitcastingApi.refreshRoom(await _stream(channel), roomId: requested, channel: channel);
  }

  /// The full room, as [getRoomDetail]: it holds everything the recorder's
  /// streams need, and the title.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  /// `streamserver.php` alone, as the follow refresh.
  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// 3.x's `HLS high`, `HLS medium`, `HLS low` from the broadcast [detail]
  /// carries, without a request; a room without one (a list card) asks
  /// `streamserver.php`. A room that is not broadcasting has none
  /// (`StreamUnavailable`, 3.x gave an empty list), and neither has a
  /// restricted one (`StreamUnavailable` with the reason): a
  /// password-protected broadcast, or a card marked private, protected or
  /// unplayable, without a request.
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
  /// without a request (REG-TWITCASTING-001), and so has a card known to be
  /// restricted. A carried broadcast decides over the card's restriction:
  /// it is the newer answer (a refreshed follow).
  Future<TwitcastingRoomData> _broadcast(LiveRoom detail, {required bool fresh}) async {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a TwitCasting room');
    if (!fresh) {
      if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '${detail.roomId} is offline');
      if (detail.data case final TwitcastingRoomData data) return data;
      if (TwitcastingApi.restricted(detail) case final SiteError error) throw error;
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
