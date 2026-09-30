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

/// How a studio answer is asked for (24-4).
enum _Use {
  /// A room entry, a recording detail or a search lookup: a fresh token,
  /// whose first use says whether the room has a password; a login gate is
  /// asked again with the same token for the state.
  entry,

  /// A follow refresh or a live-status check: the reusable token; a login
  /// gate is asked again with the same token and that answer is used.
  refresh,

  /// An input: a fresh token for the playlist, nothing asked again.
  input,
}

/// The Bigo Live adapter (3.x's `BigoSite` and `BigoApi`; parsing in
/// [BigoApi]).
///
/// Anonymous, like 3.x: no cookie and no account. 3.x's Bigo had no chat
/// (`EmptyDanmaku`); room entry and recording details now hand the chat
/// connection its arguments (`BigoDanmakuArgs`, M5.20). Every request
/// carries 3.x's headers, does not follow redirects and goes as `bigo`, so
/// the app routes the platform through its proxy setting. The requests:
/// - the catalog, the directory, the recommendations and the search filter
///   are all the public list `vedioList/72` (about 20 live rooms), paged
///   locally. Page 1 of the directory (the pull to refresh) fetches it anew;
///   every other call, the search included, reuses a list younger than
///   [snapshotLifetime] whoever fetched it (24-5; 3.x fetched anew for
///   every call with a cancel token, so the search filtered another list
///   than the one on screen). See [getDirectoryPage];
/// - a room is the anonymous web token (`webjs/t`, then `webjs/status` with
///   the encrypted request) and `getInternalStudioInfo` with it, within one
///   20 s deadline (3.x). Only a token's first use gives the playlist and
///   says whether the room has a password; every later use gives the rest
///   (24-4). So an entry, a recording detail, a search lookup and an input
///   take a fresh token (three requests, as 3.x), while follow refreshes
///   and live-status checks reuse the last token for [tokenReuse] (one
///   request each; see [getRoomDetailForRefresh]);
/// - streams have no URL: the one quality resolves to a [BigoInputRecipe];
///   playback and recording each call [resolveInput] for a fresh token and
///   playlist, and restore the scrambled segments with [BigoHlsProtection]
///   on their way through the relay (M7, M8).
///
/// Rooms are identified by the Bigo id the site writes (`clientBigoId`),
/// which is what 3.x's details returned whatever the room was asked for by;
/// list cards keep the list's `bigo_id` (3.x). The site finds an id in any
/// case, so identity ignores case (`SiteIds.caseInsensitiveRoomIds`).
/// Failures are `SiteError`s; nothing is disguised as an offline room.
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
  /// with its studio requests together (3.x: 20 s). [now], [random] (the
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

  /// How long a list is reused after it arrived (3.x's 30 s; 24-5 extends
  /// the reuse to the directory's later pages and the search).
  static const Duration snapshotLifetime = Duration(seconds: 30);

  /// How long a web token is reused by follow refreshes and live-status
  /// checks after it was issued (24-4). The site answers every use of a
  /// token after the first the same way however old it is: a token used
  /// again 1 to 60 minutes later, and a made-up one, still gave the state,
  /// names and pictures (checks of 2026-09-28/29), so the limit is a margin,
  /// not a measured expiry.
  static const Duration tokenReuse = Duration(minutes: 30);

  /// Transport.
  final LiveHttp http;

  /// Longest list fetch, or token and studio requests together.
  final Duration deadline;

  final DateTime Function() _now;
  final Random _random;
  final String Function()? _callbackName;
  Future<List<LiveRoom>>? _snapshot;
  DateTime? _snapshotAt;
  String? _token;
  DateTime? _tokenAt;
  Future<String>? _tokenFetch;

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

  /// The public list.
  ///
  /// [fresh] (page 1 of the directory: the pull to refresh) always asks
  /// anew. Otherwise the last list is reused while it is younger than
  /// [snapshotLifetime] after it arrived, whoever fetched it (24-5: 3.x
  /// fetched anew for every call with a cancel token, and the directory and
  /// search pages always pass one). A call without [cancel] also shares a
  /// fetch under way (3.x fetched again for every caller that came before
  /// the first answer); one with [cancel] only reuses a list that has
  /// arrived, and otherwise fetches its own with the token, so cancelling it
  /// never fails another caller. The latest successful fetch becomes the
  /// shared list; a failed one is forgotten.
  Future<List<LiveRoom>> _snapshotFor({CancelToken? cancel, bool fresh = false}) async {
    if (!fresh) {
      final cached = _snapshot;
      final at = _snapshotAt;
      if (cached != null && (at == null ? cancel == null : _young(at, snapshotLifetime))) {
        final cards = await cached;
        _checkCancelled(cancel);
        return cards;
      }
    }
    if (cancel == null) return await _share();
    final cards = await _fetchSnapshot(cancel);
    _snapshot = Future.value(cards);
    _snapshotAt = _now();
    return cards;
  }

  bool _young(DateTime at, Duration lifetime) {
    final age = _now().difference(at);
    return age >= Duration.zero && age < lifetime;
  }

  /// A new fetch, shared with every caller without a cancel token until it
  /// arrives, and then for [snapshotLifetime]; a failed one is forgotten.
  Future<List<LiveRoom>> _share() {
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
  /// recommendations (3.x). Page 1 (the pull to refresh) asks for a new
  /// list; later pages come from the last one while it is younger than
  /// [snapshotLifetime], so they neither repeat nor skip rooms of page 1
  /// (24-5). A page below 1 or another area is a caller error, without a
  /// request.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _checkArea(category);
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    _checkCancelled(cancel);
    return BigoApi.directoryPage(
      await _snapshotFor(cancel: cancel, fresh: page == 1),
      page: page,
    );
  }

  /// Slice [page] of [pageSize] of the public list (3.x's `_page`: a page or
  /// size below 1, or a size over 100, gives nothing, now without a
  /// request), from the shared list.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (!BigoApi.validSlice(page: page, pageSize: pageSize)) return const [];
    return BigoApi.slice(await _snapshotFor(), page: page, pageSize: pageSize);
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
  /// letters that matches no card is looked up as an id. The filter uses
  /// the list the directory showed when it is younger than
  /// [snapshotLifetime] (24-5). A lookup is the room's studio (three
  /// requests; an unknown id is no result). A blank, over-long or control
  /// keyword, a URL of another site, another page or a page size below 1
  /// gives nothing without a request.
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
    final cards = await _snapshotFor(cancel: cancel);
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
      return [BigoApi.room(await _studio(siteId, cancel, use: _Use.entry))];
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

  /// A new anonymous web token (3.x's `studioRoom` before the studio): the
  /// server time, then the token for the encrypted request.
  Future<String> _fetchToken(CancelToken cancel) async {
    final timeCallback = _callback();
    final time = await _send('GET', Uri.https(_tokenHost, '/v1/webjs/t', {'callback': timeCallback}), cancel: cancel);
    final timestamp = BigoApi.serverTime(time.text, callback: timeCallback, status: time.status);
    final statusCallback = _callback();
    final status = await _send(
      'GET',
      Uri.https(_tokenHost, '/v1/webjs/status', {
        'callback': statusCallback,
        'data': BigoApi.tokenData(timestamp, random: _random),
      }),
      cancel: cancel,
    );
    return BigoApi.token(status.text, callback: statusCallback, status: status.status);
  }

  /// Keeps [token] for refreshes, from now on for [tokenReuse] (24-4).
  void _keepToken(String token) {
    _token = token;
    _tokenAt = _now();
  }

  /// The token of a refresh: the kept one while younger than [tokenReuse],
  /// else one new token shared by every refresh that asks before it
  /// arrives (a follow list refreshes its rooms together). The fetch has its
  /// own [deadline], so no one caller's cancellation fails the others; a
  /// failed fetch is forgotten.
  Future<String> _reusableToken() {
    final token = _token;
    final at = _tokenAt;
    if (token != null && at != null && _young(at, tokenReuse)) return Future.value(token);
    return _tokenFetch ??= _scoped(null, _fetchToken).then(
      (token) {
        _keepToken(token);
        _tokenFetch = null;
        return token;
      },
      onError: (Object error, StackTrace stack) {
        _tokenFetch = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  /// `getInternalStudioInfo` of [siteId] with [webToken] (the token in the
  /// query and an empty body, 3.x).
  Future<BigoStudio> _ask(String siteId, String webToken, CancelToken cancel) async {
    final studio = await _send(
      'POST',
      Uri.https(_apiHost, '/official_website/studio/getInternalStudioInfo', {
        'siteId': siteId,
        'verify': '',
        'token': webToken,
      }),
      cancel: cancel,
    );
    return BigoApi.studio(studio.text, requestedSiteId: siteId, status: studio.status);
  }

  /// The studio of [siteId] for [use], within one [deadline] (3.x's
  /// `studioRoom`).
  ///
  /// An entry and an input take a fresh token (three requests, 3.x): only
  /// a token's first use gives the playlist and says whether the room has a
  /// password. A refresh takes the reusable token ([_reusableToken]; one
  /// request when one is kept). Every token, once used, is kept for
  /// refreshes.
  ///
  /// The site sometimes answers a token's first use with `needLogin`, all
  /// fields zeroed, and turns out to accept the same token a moment later
  /// (seen in bursts of new tokens; the same room was open again minutes
  /// later). The same token asked again (one more request, only then) gives
  /// the room's state: an entry keeps the login gate with that state (the
  /// unified rule: a gated live room is live and marked), a refresh uses
  /// that answer as it is. An input asks nothing again: a gated input has no
  /// playlist either way.
  Future<BigoStudio> _studio(String siteId, CancelToken? cancel, {required _Use use}) => _scoped(cancel, (token) async {
    final webToken = switch (use) {
      _Use.refresh => await _reusableToken(),
      _Use.entry || _Use.input => await _fetchToken(token),
    };
    final first = await _ask(siteId, webToken, token);
    if (use != _Use.refresh) _keepToken(webToken);
    if (first.access != BigoAccess.loginRequired || use == _Use.input) return first;
    final again = await _ask(siteId, webToken, token);
    if (again.access == BigoAccess.loginRequired) {
      if (_token == webToken) _tokenAt = null;
      return first;
    }
    return use == _Use.refresh ? again : again.gated();
  });

  /// A room entry and a recording detail also carry the chat arguments
  /// (`BigoDanmakuArgs` in `danmakuData`, M5.20); a refresh does not.
  Future<LiveRoom> _detail(String roomId, _Use use) async =>
      BigoApi.room(await _studio(_siteId(roomId), null, use: use), danmaku: use == _Use.entry);

  /// The room: a fresh web token and the studio (three requests, 3.x; four
  /// behind a login gate). Its id is the site's `clientBigoId`, whatever id
  /// it was asked for by. The cover is the broadcast's snapshot (24-1). A
  /// live studio whose chat the website opens carries its chat arguments
  /// ([BigoApi.danmakuArgs], M5.20), without another request.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, _Use.entry);

  /// The studio with the reusable token (24-4): one request while a token is
  /// kept (3.x: three every time), the token's two requests once in
  /// [tokenReuse]. The answer of a used token has the state, names and
  /// pictures but neither the playlist nor the password flag, so the room's
  /// restriction is left out unless the room is a paid show (the stored one
  /// is kept while the state stays the same, M2.1) and it plays like any
  /// live room: the input asks the studio again.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId, _Use.refresh);

  /// As [getRoomDetail] (three requests): recording asks the studio again
  /// for its own input ([resolveInput]).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, _Use.entry);

  /// Whether the studio says live, with the reusable token as a refresh
  /// (24-4). A restricted live room is live (M2.1). A state the studio
  /// leaves unknown is an error, never "offline": a login gate is
  /// `NeedsLogin`, a password or paid room that is not alive
  /// `StreamUnavailable`.
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final studio = await _studio(_siteId(roomId), null, use: _Use.refresh);
    return switch (studio.liveStatus) {
      LiveStatus.live => true,
      LiveStatus.offline => false,
      _ => throw studio.data.streamError ?? ApiChanged(_site, '${studio.siteId}: state unknown'),
    };
  }

  // Streams -------------------------------------------------------------------

  /// The studio data of [detail] when it can be played (3.x's checks, no
  /// request): a Bigo room, not offline, with the data of its own studio
  /// answer (the id's case aside) saying public and live, and with a
  /// playlist when the answer was complete. Otherwise the reason
  /// (`StreamUnavailable`, or `NeedsLogin` for a login gate); a card
  /// without studio data (a list card) names its restriction when it has
  /// one. Another platform's room is a caller error.
  BigoRoomData _playable(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not a Bigo room');
    final siteId = _siteId(detail.roomId);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '$siteId is offline');
    final data = detail.data;
    if (data is! BigoRoomData || data.siteId.toLowerCase() != siteId.toLowerCase()) {
      if (detail.isRestricted) throw StreamUnavailable(_site, '$siteId: ${detail.effectiveRestriction.name} room');
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
  /// [BigoRoomData.streamError]); an answer without the playlist is
  /// `StreamUnavailable`. The caller relays the playlist and restores every
  /// segment with [BigoHlsProtection] (M7, M8).
  Future<LivePlayLine> resolveInput(BigoInputRecipe recipe, {CancelToken? cancel}) async {
    final studio = await _studio(recipe.siteId, cancel, use: _Use.input);
    final error = studio.data.streamError;
    if (error != null) throw error;
    final hls = studio.hls;
    if (hls == null) throw StreamUnavailable(_site, '${studio.siteId}: no hls_src');
    return BigoApi.line(hls);
  }

  // Links ---------------------------------------------------------------------

  /// A room link of `bigo.tv` or a subdomain, a fragment ignored (3.x's
  /// `BigoLink.parse` widened by 24-7, see [BigoApi.siteIdFromUrl]); the id
  /// as written, which the room then answers with the site's spelling.
  @override
  String? roomIdFromUrl(String url) => BigoApi.siteIdFromUrl(url);
}
