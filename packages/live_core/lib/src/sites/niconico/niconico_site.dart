import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/niconico/niconico_api.dart';
import 'package:live_core/src/sites/niconico/niconico_seat.dart';
import 'package:live_net/live_net.dart';

const _site = 'niconico';
const _host = 'live.nicovideo.jp';

/// The niconico live adapter (3.x's `NiconicoSite`, `NiconicoApi`,
/// `NiconicoDirectory` and `NiconicoQualityCatalog`; parsing in
/// [NiconicoApi], the seat in [NiconicoSeat]).
///
/// Anonymous, like 3.x: every request goes as `niconico` with 3.x's
/// headers, no cookie and no redirect following. A room is one program
/// (`lv…`, the id 3.x stored), read from its watch page; the catalog is the
/// seven recent-program tabs, natively paged; search lists programs on air.
/// Streams have no URL: quality discovery opens a seat of its own, reads
/// the HLS master with the seat's cookies and closes the seat before it
/// returns; the chosen quality resolves to a [NiconicoInputRecipe] that
/// playback and recording open themselves (M7, M8). Failures are
/// `SiteError`s; nothing is disguised as an offline room.
final class NiconicoSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveQualityDiscovery,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LivePlayUrlCursorResolver {
  /// Creates the adapter. Seats connect with [connector] (default
  /// `dart:io`) through [proxy]'s route for `niconico`, the one the app
  /// gives [http] too. [discoveryDeadline] bounds a whole quality discovery
  /// and [seatStartupTimeout] the wait for a seat's first grant (3.x: 30 s
  /// and 20 s).
  new(
    this.http, {
    this.proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    this.discoveryDeadline = const Duration(seconds: 30),
    this.seatStartupTimeout = const Duration(seconds: 20),
  }) : _connector = connector ?? connectIoSocket;

  /// Transport.
  final LiveHttp http;

  /// Proxy routes of the seat WebSockets.
  final ProxyPolicy proxy;

  /// Longest quality discovery.
  final Duration discoveryDeadline;

  /// Longest wait for a seat's first grant.
  final Duration seatStartupTimeout;

  final SocketConnector _connector;

  /// How long the master playlist may take (3.x's 5 s budget).
  static const Duration masterTimeout = Duration(seconds: 5);

  @override
  String get id => _site;

  @override
  String get name => 'niconico';

  /// The text key of 3.x's directory explanation: the default directory is
  /// the recent programs of the general tab, not a ranking; search lists
  /// programs on air.
  @override
  String get directoryNoticeKey => 'niconico_directory_scope';

  // Requests ------------------------------------------------------------------

  /// GETs [url] as 3.x did: its headers (unless [headers]), no redirect
  /// following. A cancelled [cancel] sends nothing and drops a late answer.
  Future<LiveResponse> _get(
    Uri url, {
    CancelToken? cancel,
    Map<String, String> headers = NiconicoApi.headers,
    Duration timeout = defaultRequestTimeout,
  }) async {
    _checkCancelled(cancel);
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(site: _site, url: url, headers: headers, followRedirects: false, timeout: timeout, cancel: cancel),
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

  /// Pages 1–10000 and page sizes 1–100 (3.x's bounds); anything else is the
  /// caller's mistake and sends nothing.
  static void _checkPaging(int page, [int pageSize = 1]) {
    if (page < 1 || page > 10000 || pageSize < 1 || pageSize > 100) {
      throw ArgumentError('Invalid niconico page $page of $pageSize');
    }
  }

  // Catalog -------------------------------------------------------------------

  /// 3.x's one category, `niconico`, whose areas are the seven tabs (names
  /// in 3.x's Chinese; the interface translates them by area id). Only page
  /// 1 has it; no request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    _checkPaging(page, pageSize);
    return page == 1 ? [NiconicoApi.category()] : const [];
  }

  /// Page [page] (70 programs) of [category]'s tab, or of `common` (the
  /// recommendations) when null: `recent/v1/programs` with `offset` = page
  /// − 1, more while `totalCount` says so. An area that is not a niconico tab
  /// is the caller's mistake (`ArgumentError`) and sends nothing.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    final tab = _tab(category);
    _checkPaging(page);
    final response = await _get(
      Uri.https(_host, '/front/api/pages/recent/v1/programs', {
        'tab': tab,
        'offset': '${page - 1}',
        'sortOrder': 'recentDesc',
      }),
      cancel: cancel,
    );
    return NiconicoApi.directoryPage(response.text, page: page, search: false, status: response.status);
  }

  static String _tab(LiveArea? area) {
    if (area == null) return 'common';
    if (area.platform != _site || area.areaType != NiconicoApi.areaType || !NiconicoApi.tabs.contains(area.areaId)) {
      throw ArgumentError.value(area, 'category', 'not a niconico tab');
    }
    return area.areaId;
  }

  /// The `common` tab's page [page]: the site's page of 70, whatever
  /// [pageSize] (checked, 1–100, as 3.x did).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    _checkPaging(1, pageSize);
    return (await getDirectoryPage(page: page)).rooms;
  }

  /// [category]'s page [page]; see [getRecommendRooms].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _checkPaging(1, pageSize);
    return (await getDirectoryPage(page: page, category: category)).rooms;
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Programs on air matching [keyword]: the site's page of 40, whatever
  /// [pageSize] (checked, 1–100). A blank keyword gives nothing without a
  /// request; a keyword over 500 characters or a page out of range is the
  /// caller's mistake (`ArgumentError`), as in 3.x.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    _checkCancelled(cancel);
    _checkPaging(page, pageSize);
    if (keyword.length > 500) throw ArgumentError('A niconico keyword has at most 500 characters');
    final term = keyword.trim();
    if (term.isEmpty) return const [];
    final response = await _get(
      Uri.https(_host, '/front/api/pages/search/v1/programs', {
        'keyword': term,
        'column': 'main',
        'status': 'onair',
        'page': '$page',
        'disableGrouping': 'true',
      }),
      cancel: cancel,
    );
    return NiconicoApi.directoryPage(response.text, page: page, search: true, status: response.status).rooms;
  }

  // Rooms ---------------------------------------------------------------------

  /// [roomId] as a program id; anything else is `NotFound` without a
  /// request (3.x's identity check).
  static String _programId(String roomId) {
    final id = roomId.trim();
    if (!NiconicoApi.isProgramId(id)) throw NotFound(_site, 'room id "$id" is not a niconico program');
    return id;
  }

  Future<NiconicoWatch> _watch(String programId, {CancelToken? cancel}) async {
    final response = await _get(Uri.parse(NiconicoApi.watchUrl(programId)), cancel: cancel);
    return NiconicoApi.watch(response.text, programId: programId, status: response.status);
  }

  Future<LiveRoom> _detail(String roomId) async => NiconicoApi.room(await _watch(_programId(roomId)));

  /// The program's watch page (one request). The seat bootstrap on it is
  /// short-lived and is not kept; streams read the page again.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  /// The same one request, as in 3.x.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The same one request: recording opens its own seat from the recipe.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId)).isLiveNow;

  // Seats ---------------------------------------------------------------------

  /// Reads [programId]'s watch page and opens a seat on it: the grant of a
  /// program on air that an anonymous viewer may watch. Not on air is
  /// `StreamUnavailable`; a restricted program `RegionBlocked` or
  /// `NeedsLogin`, without a connection (3.x's checks). The caller owns the
  /// seat and closes it; playback and recording open one each (M7, M8).
  Future<NiconicoSeat> openSeat(String programId, {CancelToken? cancel}) async {
    final watch = await _watch(_programId(programId), cancel: cancel);
    final error = watch.streamError;
    if (error != null) throw error;
    final socket = watch.socket;
    if (socket == null) throw ApiChanged(_site, 'watch page: $programId has no seat');
    return await NiconicoSeat.open(
      socket,
      connector: _connector,
      route: proxy.routeFor(_site, socket),
      cancel: cancel,
      startupTimeout: seatStartupTimeout,
    );
  }

  // Streams -------------------------------------------------------------------

  String _streamProgram(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a niconico room');
    return _programId(detail.roomId);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) =>
      discoverPlayQualitiesRaw(detail: detail);

  /// The program's exact variants (3.x's quality catalog): the watch page
  /// again, a seat of its own, the master with the seat's cookies for its
  /// path; the seat is closed before this returns. A room the platform said
  /// is offline has none (`StreamUnavailable` without a request; 3.x gave
  /// an empty list).
  ///
  /// Bounded by [discoveryDeadline] (`NetworkFailure`) and [cancel] (a
  /// cancelled `TransportFailure`, also when it arrives while the seat
  /// closes). A seat that ends, or moves the stream to another master,
  /// while the master is read fails the discovery with its reason.
  @override
  Future<List<LivePlayQuality>> discoverPlayQualitiesRaw({required LiveRoom detail, CancelToken? cancel}) async {
    _checkCancelled(cancel);
    final programId = _streamProgram(detail);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '$programId is offline');
    final token = CancelToken();
    Exception? reason;
    void stop(Exception why) {
      reason ??= why;
      token.cancel();
    }

    if (cancel != null) {
      unawaited(cancel.whenCancelled.then((_) => stop(const TransportFailure(_site, TransportReason.cancelled))));
    }
    final deadline = Timer(
      discoveryDeadline,
      () => stop(NetworkFailure(_site, 'quality discovery over ${discoveryDeadline.inSeconds} s')),
    );
    NiconicoSeat? seat;
    StreamSubscription<NiconicoGrant>? moves;
    var finished = false;
    late final List<LivePlayQuality> qualities;
    try {
      final owner = seat = await openSeat(programId, cancel: token);
      final source = owner.current.uri;
      moves = owner.changes.listen((grant) {
        if (grant.uri != source) stop(const StreamUnavailable(_site, 'the seat moved the stream to another master'));
      });
      unawaited(
        owner.done.then((failure) {
          if (!finished) stop(failure ?? const StreamUnavailable(_site, 'the seat was closed'));
        }),
      );
      final cookie = owner.current.cookieHeaderFor(source);
      final response = await _get(source, cancel: token, headers: {'cookie': ?cookie}, timeout: masterTimeout);
      final ended = reason;
      if (ended != null) throw ended;
      qualities = NiconicoApi.qualities(response.text, source: source, programId: programId, status: response.status);
    } on TransportFailure catch (failure) {
      if (failure.reason != TransportReason.cancelled) rethrow;
      throw reason ?? failure;
    } finally {
      finished = true;
      deadline.cancel();
      await moves?.cancel();
      await seat?.close();
    }
    _checkCancelled(cancel);
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The recipe of [quality] (3.x's owned input): no URL, no seat. A room
  /// the platform said is offline is `StreamUnavailable`; a quality that is
  /// not one of this program's (another program's, or a relabelled one) is
  /// the caller's mistake. The applied quality is the one asked for.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final programId = _streamProgram(detail);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '$programId is offline');
    final choice = quality.data;
    if (choice is! NiconicoQuality || choice.programId != programId || quality.selectionId != choice.id) {
      throw ArgumentError.value(quality, 'quality', 'not a quality of $programId');
    }
    return LivePlayUrlResolution.owned(
      input: NiconicoInputRecipe(programId: programId, resolution: choice.resolution, bandwidth: choice.bandwidth),
      appliedQualityData: choice.id,
    );
  }

  /// The same recipe: every open already reads the watch page and takes a
  /// fresh seat.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => resolvePlayUrlsRaw(detail: detail, quality: quality);

  /// One line, the recipe; a later line has nothing (3.x).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlAtRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
    required int lineIndex,
  }) async {
    if (lineIndex != 0) return LivePlayUrlResolution(urls: const []);
    return await resolvePlayUrlsRaw(detail: detail, quality: quality);
  }

  // Links ---------------------------------------------------------------------

  /// An https watch link of a program (3.x's `NiconicoLink`, see
  /// [NiconicoApi.programIdFromUrl]).
  @override
  String? roomIdFromUrl(String url) => NiconicoApi.programIdFromUrl(url);
}
