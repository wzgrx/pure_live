import 'dart:async';
import 'dart:math';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/bigo/bigo_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'bigo';

/// The public list and the studio API.
const _apiHost = 'ta.bigo.tv';

/// The web token service.
const _tokenHost = 'sec.bigo.sg';

/// How long a list fetched without a cancel token is reused (3.x).
const _snapshotLifetime = Duration(seconds: 30);

/// The Bigo Live adapter (3.x's `BigoSite` and `BigoApi`; parsing in
/// [BigoApi]).
///
/// Anonymous, like 3.x: no cookie, no account and no chat (3.x's Bigo had
/// `EmptyDanmaku`). Every request carries 3.x's headers, does not follow
/// redirects and goes as `bigo`, so the app routes the platform through its
/// proxy setting. The requests are 3.x's:
/// - the catalog, the directory, the recommendations and the search filter
///   are all the public list `vedioList/72` (about 20 live rooms), paged
///   locally. A list asked for without a cancel token is shared for 30 s
///   (and while it is being fetched); one asked for with a token (the
///   directory and search pages always pass one) is fetched anew, as in
///   3.x;
/// - a room is the anonymous web token (`webjs/t`, then `webjs/status` with
///   the encrypted request) and `getInternalStudioInfo` with it, three
///   requests at every depth, within one 20 s deadline (3.x);
/// - streams have no URL: the one quality resolves to a [BigoInputRecipe];
///   playback and recording each call [resolveInput] for a fresh token and
///   playlist, and restore the scrambled segments with [BigoHlsProtection]
///   on their way through the relay (M7, M8).
///
/// Rooms are identified by the Bigo id the site writes (`clientBigoId`),
/// which is what 3.x's details returned whatever the room was asked for by;
/// list cards keep the list's `bigo_id` (3.x). Failures are `SiteError`s;
/// nothing is disguised as an offline room.
final class BigoSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter. [deadline] bounds a list fetch, and a web token
  /// with its studio request together (3.x: 20 s). [now], [random] (the
  /// token request's salt and nonce) and `callbackName` (the JSONP callback
  /// of each token request, 3.x's `jsonpcallback_<ms>_<µs>` by default) are
  /// injectable for tests.
  new(
    this.http, {
    this.deadline = const Duration(seconds: 20),
    DateTime Function()? now,
    Random? random,
    this._callbackName,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  /// Transport.
  final LiveHttp http;

  /// Longest list fetch, or token and studio request together.
  final Duration deadline;

  final DateTime Function() _now;
  final Random _random;
  final String Function()? _callbackName;
  Future<List<LiveRoom>>? _snapshot;
  DateTime? _snapshotAt;

  @override
  String get id => _site;

  @override
  String get name => BigoApi.siteName;

  /// 3.x's text key for the directory's scope note (a finite recommendation
  /// snapshot; the search filters it and looks ids and links up).
  @override
  String get directoryNoticeKey => 'bigo_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A [method] request of [url] with 3.x's headers, redirects not followed,
  /// an empty body for POST (3.x sent the studio request without one). A
  /// cancellation before the request or while it runs is a cancelled
  /// `TransportFailure`, also when the answer (or a transport failure)
  /// arrived meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _send(String method, Uri url, {required CancelToken cancel}) async {
    _checkCancelled(cancel);
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(
          site: _site,
          method: method,
          url: url,
          headers: BigoApi.headers,
          body: method == 'POST' ? const <int>[] : null,
          followRedirects: false,
          cancel: cancel,
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      _checkCancelled(cancel);
      throw NetworkFailure(_site, failure.toString());
    }
    _checkCancelled(cancel);
    return response;
  }

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  /// [work] under its own token, cancelled by [cancel] or when [deadline]
  /// passes (3.x's `_scope`): the caller's cancellation is a cancelled
  /// `TransportFailure`, the deadline a `NetworkFailure`.
  Future<T> _scoped<T>(CancelToken? cancel, Future<T> Function(CancelToken token) work) async {
    _checkCancelled(cancel);
    final token = CancelToken();
    var expired = false;
    final timer = Timer(deadline, () {
      expired = true;
      token.cancel();
    });
    if (cancel != null) unawaited(cancel.whenCancelled.then((_) => token.cancel()));
    try {
      return await Future.any<T>([
        work(token),
        token.whenCancelled.then<T>((_) => throw const TransportFailure(_site, TransportReason.cancelled)),
      ]);
    } on TransportFailure catch (failure) {
      if (failure.reason != TransportReason.cancelled || !expired || (cancel?.isCancelled ?? false)) rethrow;
      throw NetworkFailure(_site, 'no answer within ${deadline.inSeconds} s');
    } finally {
      timer.cancel();
    }
  }

  // Public list ---------------------------------------------------------------

  Future<List<LiveRoom>> _fetchSnapshot(CancelToken? cancel) => _scoped(cancel, (token) async {
    final response = await _send(
      'GET',
      Uri.https(_apiHost, '/official_website/OInterfaceWeb/vedioList/72', {
        'tabType': '00',
        'fetchNum': '10',
        'lang': 'en',
        'countryCode': 'US',
      }),
      cancel: token,
    );
    return BigoApi.directory(response.text, status: response.status);
  });

  /// The public list. With [cancel] it is always fetched anew (3.x: a
  /// cancellable caller never shares a request). Without, the last one is
  /// reused for 30 s after it arrived, and a fetch under way is shared (3.x
  /// fetched again for every caller that came before the first answer); a
  /// failed fetch is forgotten.
  Future<List<LiveRoom>> _snapshotFor(CancelToken? cancel) {
    if (cancel != null) return _fetchSnapshot(cancel);
    final cached = _snapshot;
    final at = _snapshotAt;
    if (cached != null && (at == null || _now().difference(at) < _snapshotLifetime)) return cached;
    late final Future<List<LiveRoom>> fetch;
    fetch = _fetchSnapshot(null).then(
      (cards) {
        if (identical(_snapshot, fetch)) _snapshotAt = _now();
        return cards;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_snapshot, fetch)) {
          _snapshot = null;
          _snapshotAt = null;
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _snapshot = fetch;
    _snapshotAt = null;
    return fetch;
  }

  /// Another area than the one public list is a caller error.
  static void _checkArea(LiveArea? category) {
    if (category != null && !BigoApi.isArea(category)) {
      throw ArgumentError.value(category, 'category', 'not the Bigo public list');
    }
  }

  // Catalog and directory -----------------------------------------------------

  /// 3.x's one category `Bigo Live` with its one area (the public list), on
  /// page 1 with a page size of at least 1; no request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async =>
      page == 1 && pageSize >= 1 ? BigoApi.categories() : const [];

  /// Page [page] (20 rooms) of the public list, for the one area or the
  /// recommendations (3.x). A page below 1 or another area is a caller
  /// error, without a request.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _checkArea(category);
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    _checkCancelled(cancel);
    return BigoApi.directoryPage(await _snapshotFor(cancel), page: page);
  }

  /// Slice [page] of [pageSize] of the public list (3.x's `_page`: a page or
  /// size below 1, or a size over 100, gives nothing, now without a
  /// request).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (!BigoApi.validSlice(page: page, pageSize: pageSize)) return const [];
    return BigoApi.slice(await _snapshotFor(null), page: page, pageSize: pageSize);
  }

  /// The one area's rooms: [getRecommendRooms].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _checkArea(category);
    return await getRecommendRooms(page: page, pageSize: pageSize);
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search, first page only (Bigo's web search endpoints answer
  /// nothing): a room link is looked up by its id; a keyword that looks like
  /// an id (with a digit, `_`, `.` or `-`) is looked up first; otherwise the
  /// public list is filtered by streamer name and topic, and a word of
  /// letters that matches no card is looked up as an id. A lookup is the
  /// room's studio (three requests; an unknown id is no result). A blank,
  /// over-long or control keyword, a URL of another site, another page or a
  /// page size below 1 gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    _checkCancelled(cancel);
    if (page != 1 || pageSize < 1) return const [];
    final query = keyword.trim();
    final linked = BigoApi.siteIdFromUrl(query);
    if (linked != null) return await _lookUp(linked, cancel);
    if (!BigoApi.isSearchable(query)) return const [];
    final siteId = BigoApi.siteIdOf(query);
    final asId = BigoApi.looksLikeId(query);
    if (asId) {
      final exact = await _lookUp(query, cancel);
      if (exact.isNotEmpty) return exact;
    }
    final cards = await _snapshotFor(cancel);
    _checkCancelled(cancel);
    final asName = siteId != null && !asId;
    if (asName && cards.any((card) => card.roomId.toLowerCase() == query.toLowerCase())) {
      return await _lookUp(siteId, cancel);
    }
    final matches = BigoApi.filter(cards, query);
    if (matches.isNotEmpty) return matches;
    return asName ? await _lookUp(siteId, cancel) : const [];
  }

  /// The room of [siteId] as one result, or none when the site does not know
  /// it (3.x's `_exactSearch`).
  Future<List<LiveRoom>> _lookUp(String siteId, CancelToken? cancel) async {
    try {
      return [BigoApi.room(await _studio(siteId, cancel))];
    } on NotFound {
      return const [];
    }
  }

  // Rooms ---------------------------------------------------------------------

  /// [roomId] as a Bigo id; anything else is `NotFound` without a request
  /// (3.x's identity check).
  static String _siteId(String roomId) {
    final id = roomId.trim();
    if (!BigoApi.isSiteId(id)) throw NotFound(_site, 'room id "$id" is not a Bigo id');
    return id;
  }

  String _callback() {
    final name = _callbackName?.call() ?? BigoApi.callbackName(_now());
    if (!BigoApi.isCallbackName(name)) throw StateError('"$name" is not a JSONP callback name');
    return name;
  }

  /// The studio of [siteId] with a fresh anonymous web token (3.x's
  /// `studioRoom`): the server time, the token for the encrypted request,
  /// then `getInternalStudioInfo` with it, within one [deadline].
  Future<BigoStudio> _studio(String siteId, CancelToken? cancel) => _scoped(cancel, (token) async {
    final timeCallback = _callback();
    final time = await _send('GET', Uri.https(_tokenHost, '/v1/webjs/t', {'callback': timeCallback}), cancel: token);
    final timestamp = BigoApi.serverTime(time.text, callback: timeCallback, status: time.status);
    final statusCallback = _callback();
    final status = await _send(
      'GET',
      Uri.https(_tokenHost, '/v1/webjs/status', {
        'callback': statusCallback,
        'data': BigoApi.tokenData(timestamp, random: _random),
      }),
      cancel: token,
    );
    final webToken = BigoApi.token(status.text, callback: statusCallback, status: status.status);
    final studio = await _send(
      'POST',
      Uri.https(_apiHost, '/official_website/studio/getInternalStudioInfo', {
        'siteId': siteId,
        'verify': '',
        'token': webToken,
      }),
      cancel: token,
    );
    return BigoApi.studio(studio.text, requestedSiteId: siteId, status: studio.status);
  });

  Future<LiveRoom> _detail(String roomId) async => BigoApi.room(await _studio(_siteId(roomId), null));

  /// The room: the web token and the studio (three requests, 3.x). Its id is
  /// the site's `clientBigoId`, whatever id it was asked for by.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  /// The same three requests (3.x).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The same three requests: recording asks the studio again for its own
  /// input ([resolveInput]).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  /// Whether the studio says live (three requests, 3.x). A state the studio
  /// leaves unknown is an error, never "offline": a login gate is
  /// `NeedsLogin`, a password or paid room and a live one without a playlist
  /// `StreamUnavailable`.
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final studio = await _studio(_siteId(roomId), null);
    return switch (studio.liveStatus) {
      LiveStatus.live => true,
      LiveStatus.offline => false,
      _ => throw studio.data.streamError ?? ApiChanged(_site, '${studio.siteId}: state unknown'),
    };
  }

  // Streams -------------------------------------------------------------------

  /// The studio data of [detail] when it can be played (3.x's checks, no
  /// request): a Bigo room, not offline, with the data of its own studio
  /// answer (a list card has none) saying public, live and with a playlist.
  /// Otherwise the reason (`StreamUnavailable`, or `NeedsLogin` for a login
  /// gate); another platform's room is a caller error.
  BigoRoomData _playable(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a Bigo room');
    final siteId = _siteId(detail.roomId);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '$siteId is offline');
    final data = detail.data;
    if (data is! BigoRoomData || data.siteId != siteId) {
      throw StreamUnavailable(_site, '$siteId has no studio answer; open the room first');
    }
    final error = data.streamError;
    if (error != null) throw error;
    if (!detail.isLiveNow) throw StreamUnavailable(_site, '$siteId is not live');
    return data;
  }

  /// 3.x's one quality, 直播自动, when the room can be played (no request).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    _playable(detail);
    return const [BigoApi.quality];
  }

  /// No URL (3.x): the input has none to export.
  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The recipe of the room (3.x's owned input): no URL, no request. A room
  /// that cannot be played says why (see [getPlayQualities]); a quality
  /// other than [BigoApi.quality] is a caller error. The applied quality is
  /// the one asked for.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = _playable(detail);
    if ('${quality.selectionId}' != BigoApi.qualityId) {
      throw ArgumentError.value(quality, 'quality', 'not a Bigo quality');
    }
    return LivePlayUrlResolution.owned(input: BigoInputRecipe(data.siteId), appliedQualityData: BigoApi.qualityId);
  }

  /// The same recipe: every open of it asks the studio again.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => resolvePlayUrlsRaw(detail: detail, quality: quality);

  /// The media of [recipe] for one playback or recording (3.x's
  /// `BigoHlsInput.open` before its relay): a fresh web token and studio
  /// answer on every call, never shared between consumers or reused after a
  /// failure (REG-LEASE-005, REG-LEASE-007), and the playlist as a line with
  /// 3.x's headers. A studio that cannot be played says why (see
  /// [BigoRoomData.streamError]). The caller relays the playlist and
  /// restores every segment with [BigoHlsProtection] (M7, M8).
  Future<LivePlayLine> resolveInput(BigoInputRecipe recipe, {CancelToken? cancel}) async {
    final studio = await _studio(recipe.siteId, cancel);
    final error = studio.data.streamError;
    if (error != null) throw error;
    return BigoApi.line(studio.hls!);
  }

  // Links ---------------------------------------------------------------------

  /// A room link of `bigo.tv` (3.x's `BigoLink.parse`, see
  /// [BigoApi.siteIdFromUrl]); the id as written, which the room then
  /// answers with the site's spelling.
  @override
  String? roomIdFromUrl(String url) => BigoApi.siteIdFromUrl(url);
}
