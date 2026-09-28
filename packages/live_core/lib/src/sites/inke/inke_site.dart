import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/inke/inke_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'inke';

/// The Inke (映客) adapter (3.x's `InkeSite`; parsing in [InkeApi]).
///
/// Anonymous, like 3.x: no cookie, no account and no danmaku (3.x's Inke
/// had `EmptyDanmaku`). The requests carry 3.x's headers:
/// - the recommendations are the app's hot list `api/live/simpleall`
///   (UPGRADES 14-1); the catalog and channel pages are
///   `web/Live_channel_pc`, whose areas start with the website's top list
///   `web/Live_top_pc` (3.x's recommendations). One page each; pages after
///   the first reuse the first page's answer for [snapshotLifetime];
/// - a nickname search filters those three lists (14-2); a uid or room link
///   finds that room;
/// - room entry, follow refreshes and recordings read `web/live_share_pc`
///   and, for a live room, the app's `api/live/now_publish` (14-3, 14-4);
/// - streams: `now_publish` (a freshly signed URL each time, or the room
///   entry's answer within [answerReuse]). 3.x looked for the broadcast in
///   the website showcases instead and could not play anything outside
///   them (REG-INKE-001); that lookup stays as the fallback of the H.264
///   line.
///
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class InkeSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LiveCancellableSearch,
        LiveSearchPaginationPolicy {
  /// Creates the adapter. [preferH264] reads "优先 H.264" (on by default,
  /// the setting shared with 22-3) at each call: on, a room's H.264 quality
  /// ([InkeApi.flv]) comes before the original HEVC one ([InkeApi.original]),
  /// so it is the default; off, the original comes first (14-5). [now] (the
  /// leases, the snapshots' and answers' age) is injectable for tests.
  new(this.http, {bool Function()? preferH264, DateTime Function()? now})
    : _preferH264 = preferH264 ?? _on,
      _now = now ?? DateTime.now;

  /// How long pages after the first reuse the list answers the first page
  /// fetched (UPGRADES "翻页"): a page 1 always asks anew (a pull to
  /// refresh), later slices of the same list and later search pages share
  /// its snapshot, so the app's hot list, different at each request, pages
  /// without repeats or gaps.
  static const Duration snapshotLifetime = Duration(seconds: 30);

  /// How long the room entry's `now_publish` answer serves a play of that
  /// room instead of a new request (its lines are signed for hours): the
  /// first play right after entering or recording costs no request. Renewals
  /// come much later and recoveries always ask anew.
  static const Duration answerReuse = Duration(seconds: 30);

  /// Transport.
  final LiveHttp http;

  final bool Function() _preferH264;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, LiveResponse response})> _snapshots = {};

  static bool _on() => true;

  @override
  String get id => _site;

  @override
  String get name => '映客';

  /// 3.x's text key for the directory's scope note. Its text is the UI's
  /// (M13) and is to be rewritten (14-6): the recommendations are the app's
  /// hot list, the areas the website's showcases, neither a full list, and
  /// every live room plays.
  @override
  String get directoryNoticeKey => 'inke_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [url] with 3.x's headers, redirects not followed (as 3.x). A
  /// cancellation before the request or while it runs is a cancelled
  /// `TransportFailure`, also when the answer (or a transport failure)
  /// arrived meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _get(Uri url, {CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(
        LiveRequest(site: _site, url: url, headers: InkeApi.headers, followRedirects: false, cancel: cancel),
      );
      _checkCancelled(cancel);
      return response;
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      _checkCancelled(cancel);
      throw NetworkFailure(_site, failure.toString());
    }
  }

  /// A list endpoint's answer: [fresh] (a first page) asks anew and keeps a
  /// successful answer as the snapshot; otherwise a snapshot younger than
  /// [snapshotLifetime] is reused.
  Future<LiveResponse> _list(Uri url, {required bool fresh, CancelToken? cancel}) async {
    final key = '$url';
    if (!fresh) {
      final snapshot = _snapshots[key];
      final age = snapshot == null ? null : _now().difference(snapshot.at);
      if (snapshot != null && age! >= Duration.zero && age < snapshotLifetime) {
        _checkCancelled(cancel);
        return snapshot.response;
      }
    }
    final response = await _get(url, cancel: cancel);
    if (response.status == 200) _snapshots[key] = (at: _now(), response: response);
    return response;
  }

  static Uri _web(String path, [Map<String, String>? query]) =>
      Uri.parse('${InkeApi.webApi}/$path').replace(queryParameters: query);

  static Uri _app(String path, [Map<String, String>? query]) =>
      Uri.parse('${InkeApi.appApi}/$path').replace(queryParameters: query);

  static final Uri _hot = _app('simpleall');
  static final Uri _top = _web('Live_top_pc');
  static final Uri _channels = _web('Live_channel_pc');

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  // Catalog and directory -----------------------------------------------------

  /// The one category 映客: the website's top list and its channels as
  /// areas (see [InkeApi.categories]); later pages are empty, without a
  /// request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1) return const [];
    final response = await _list(_channels, fresh: true);
    return InkeApi.categories(response.text, status: response.status);
  }

  /// The app's hot list when [category] is null, else the area's showcase:
  /// one page. Page 2 and later are empty, without a request. A page below
  /// 1 or an area that is not an Inke showcase is a caller error, without a
  /// request.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    _checkArea(category);
    _checkCancelled(cancel);
    if (page > 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    return await _page(category, fresh: true, cancel: cancel);
  }

  static void _checkArea(LiveArea? category) {
    if (category != null &&
        (category.platform.trim().toLowerCase() != _site || category.areaType != InkeApi.areaType)) {
      throw ArgumentError.value(category, 'category', 'not an Inke showcase');
    }
  }

  Future<LiveDirectoryPage> _page(LiveArea? category, {required bool fresh, CancelToken? cancel}) async {
    if (category == null) {
      final response = await _list(_hot, fresh: fresh, cancel: cancel);
      return InkeApi.hotPage(response.text, status: response.status);
    }
    if (category.areaId == InkeApi.topArea.areaId) {
      final response = await _list(_top, fresh: fresh, cancel: cancel);
      return InkeApi.topPage(response.text, status: response.status);
    }
    final response = await _list(_channels, fresh: fresh, cancel: cancel);
    return InkeApi.channelPage(response.text, tabKey: category.areaId, status: response.status);
  }

  /// Slice [page] of [pageSize] of the hot list (3.x's `_slice`): page 1
  /// requests the list, later slices reuse it (see [snapshotLifetime]).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) => _slice(page, pageSize);

  /// As [getRecommendRooms], for [category].
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) =>
      _slice(page, pageSize, category: category);

  Future<List<LiveRoom>> _slice(int page, int pageSize, {LiveArea? category}) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (pageSize < 1) throw RangeError.range(pageSize, 1, null, 'pageSize');
    _checkArea(category);
    final rooms = (await _page(category, fresh: page == 1)).rooms;
    // Checked before multiplying, so huge pages never overflow (3.x).
    if (page - 1 > rooms.length ~/ pageSize) return const [];
    final start = (page - 1) * pageSize;
    if (start >= rooms.length) return const [];
    return rooms.sublist(start, (start + pageSize).clamp(start, rooms.length));
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Rooms for [keyword] (3.x's rules):
  /// - a page or [pageSize] below 1 is a caller error, without a request;
  /// - a uid or Inke room link finds that room on page 1 only, or nothing
  ///   when the site answers 404 (an offline room has no name: the answer
  ///   has no profile);
  /// - another link (a URL with a scheme and host) or a blank keyword finds
  ///   nothing, without a request;
  /// - anything else filters the nicknames of the top list, the channels
  ///   and the app's hot list (see [InkeApi.searchShowcases]); page 1 asks
  ///   the three anew, later pages reuse them (see [snapshotLifetime]). The
  ///   hot list failing leaves its rooms out. A page over 10000, a
  ///   [pageSize] over 60 or a keyword over 100 characters is refused
  ///   without a request, as 3.x refused them.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if (pageSize < 1) throw RangeError.range(pageSize, 1, null, 'pageSize');
    final input = keyword.trim();
    final uid = _exactRoom(input);
    if (uid != null) {
      if (page != 1) return const [];
      try {
        return [await _detail(uid, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    if (_isLink(input)) return const [];
    if (page > 10000) throw RangeError.range(page, 1, 10000, 'page');
    if (pageSize > 60) throw RangeError.range(pageSize, 1, 60, 'pageSize');
    if (input.toLowerCase().length > 100) throw ArgumentError.value(keyword, 'keyword', 'over 100 characters');
    if (input.isEmpty) return const [];
    final fresh = page == 1;
    final top = await _list(_top, fresh: fresh, cancel: cancel);
    final showcase = InkeApi.topPage(top.text, status: top.status).rooms;
    final channels = await _list(_channels, fresh: fresh, cancel: cancel);
    final channelRooms = InkeApi.channelRooms(channels.text, status: channels.status);
    List<LiveRoom> hot;
    try {
      final response = await _list(_hot, fresh: fresh, cancel: cancel);
      hot = InkeApi.hotPage(response.text, status: response.status).rooms;
    } on SiteError {
      hot = const [];
    }
    return InkeApi.searchShowcases(input, [...showcase, ...channelRooms], hot: hot, page: page, pageSize: pageSize);
  }

  /// A uid or room link is one exact answer, never pages; so is a link that
  /// is not a room.
  @override
  bool supportsSearchPaginationFor(String keyword) {
    final input = keyword.trim();
    return input.isNotEmpty && _exactRoom(input) == null && !_isLink(input);
  }

  /// The room [input] names exactly: a uid, or a room link.
  static String? _exactRoom(String input) =>
      InkeApi.idPattern.hasMatch(input) ? input : InkeApi.roomIdFromUri(Uri.tryParse(input));

  /// Whether [input] is a link (`scheme://…`) rather than a keyword. 3.x
  /// took any text with a scheme for one, so keywords such as `Re:Zero`
  /// found nothing.
  static bool _isLink(String input) {
    final uri = Uri.tryParse(input);
    return uri != null && uri.hasScheme && uri.hasAuthority;
  }

  // Rooms ---------------------------------------------------------------------

  /// `live_share_pc` as the room [roomId] (see [InkeApi.detail]) and, when
  /// it is live and [withApp], the app's broadcast ([InkeApi.withBroadcast]).
  /// The app failing, or saying the anchor is not live, leaves the room as
  /// the website gave it (the stream request reports it). An id that is not
  /// a uid is `NotFound` without a request.
  Future<LiveRoom> _detail(String roomId, {CancelToken? cancel, bool withApp = true}) async {
    final uid = roomId.trim();
    if (!InkeApi.idPattern.hasMatch(uid)) throw NotFound(_site, 'not a uid: $uid');
    final response = await _get(_web('live_share_pc', {'uid': uid}), cancel: cancel);
    final room = InkeApi.detail(response.text, uid: uid, status: response.status);
    if (!withApp || !room.isLiveNow) return room;
    try {
      final (broadcast, at) = await _broadcast(uid, cancel: cancel);
      return broadcast == null ? room : InkeApi.withBroadcast(room, broadcast, receivedAt: at);
    } on SiteError {
      return room;
    }
  }

  /// `now_publish` for [uid] and when it was received.
  Future<(InkeBroadcast?, DateTime)> _broadcast(String uid, {CancelToken? cancel}) async {
    final response = await _get(_app('now_publish', {'id': uid}), cancel: cancel);
    final at = _now();
    return (InkeApi.broadcast(response.text, uid: uid, status: response.status), at);
  }

  /// The room: `live_share_pc`, and `now_publish` when live (the app's
  /// title, cover, audience and start time; its lines serve the first
  /// play). 3.x also looked for the pull URL here and failed the whole room
  /// when the showcases did not hold it; the stream is now resolved when
  /// played ([resolvePlayUrlsRaw]).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  /// As [getRoomDetail] (3.x read the same single request; the live rooms'
  /// app answer is one more, 14-4): `mergeFrom` keeps the rest.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The room the recorder starts from, as [getRoomDetail]; its lines come
  /// from [resolvePlayUrlsRaw].
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  /// Whether the website says live (one request); a failed request is an
  /// error, never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId, withApp: false)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// The qualities, without a request: 3.x's FLV ([InkeApi.flv], H.264),
  /// and the original ([InkeApi.original], HEVC) when the room entry's app
  /// answer has its line. With "优先 H.264" on (the default) FLV comes first,
  /// else the original. A room the platform called offline is
  /// `StreamUnavailable` (3.x returned no qualities); whether a live or
  /// pending room plays is settled when its lines are resolved.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '${detail.roomId} is not live');
    final data = detail.data;
    if (data is! InkeRoomData || data.broadcast?.originUrl == null) return const [InkeApi.flv];
    return _preferH264() ? const [InkeApi.flv, InkeApi.original] : const [InkeApi.original, InkeApi.flv];
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The line of [quality] for the room's current broadcast, with the media
  /// headers and its lease: the room entry's app answer when it is younger
  /// than [answerReuse], else a freshly signed one (see [_resolve]). A room
  /// the platform called offline, or a quality other than [InkeApi.flv] and
  /// [InkeApi.original], is `StreamUnavailable` without a request.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, '${detail.roomId} is not live');
    return await _resolve(detail, quality, reuse: true);
  }

  /// A freshly signed line, as [resolvePlayUrlsRaw], whatever the room's
  /// last known state (3.x read the room again).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality, reuse: false);

  /// The lines of [quality] for [detail]'s anchor:
  /// 1. The app's broadcast: the room entry's when [reuse] and it is younger
  ///    than [answerReuse], else `now_publish`. When the app says the anchor
  ///    is not live, that is `StreamUnavailable` and nothing else is asked.
  /// 2. [InkeApi.original]: its Zego line; none is `StreamUnavailable`, and
  ///    the app failing is reported.
  /// 3. [InkeApi.flv]: its Wangsu line; when the app gave none, or failed,
  ///    3.x's lookup: the showcases in [InkeApi.showcasePaths] order, for the
  ///    broadcast the app named or else the room entry's, until one holds
  ///    it. The app's failure is reported when none does; without either
  ///    broadcast id it is reported at once.
  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality, {required bool reuse}) async {
    final selection = '${quality.selectionId}';
    final original = selection == '${InkeApi.original.selectionId}';
    if (!original && selection != '${InkeApi.flv.selectionId}') {
      throw StreamUnavailable(_site, 'quality $selection is not offered');
    }
    final uid = detail.roomId.trim();
    if (!InkeApi.idPattern.hasMatch(uid)) throw NotFound(_site, 'not a uid: $uid');
    final data = detail.data is InkeRoomData ? detail.data! as InkeRoomData : null;
    InkeBroadcast? broadcast;
    var issuedAt = _now();
    SiteError? appFailure;
    final known = data?.broadcast;
    final knownAt = data?.receivedAt;
    final age = knownAt == null ? null : issuedAt.difference(knownAt);
    if (reuse && known != null && age != null && age >= Duration.zero && age < answerReuse) {
      broadcast = known;
      issuedAt = knownAt!;
    } else {
      try {
        final (answer, at) = await _broadcast(uid);
        if (answer == null) throw StreamUnavailable(_site, '$uid is not live');
        broadcast = answer;
        issuedAt = at;
      } on StreamUnavailable {
        rethrow;
      } on SiteError catch (error) {
        if (original) rethrow;
        appFailure = error;
      }
    }
    if (original) {
      final url = broadcast!.originUrl;
      if (url == null) throw StreamUnavailable(_site, '$uid: no original (Zego) line');
      return InkeApi.originalResolution(url, issuedAt: issuedAt);
    }
    if (broadcast?.pullUrl case final url?) return InkeApi.resolution([url], issuedAt: issuedAt);
    final liveId = broadcast?.liveId ?? data?.liveId;
    if (liveId == null) throw appFailure ?? StreamUnavailable(_site, '$uid: no pull URL');
    for (final path in InkeApi.showcasePaths) {
      final response = await _get(_web(path));
      final urls = InkeApi.showcaseUrls(response.text, path: path, uid: uid, liveId: liveId, status: response.status);
      if (urls.isNotEmpty) return InkeApi.resolution(urls, issuedAt: _now());
    }
    throw appFailure ?? StreamUnavailable(_site, '$uid: no pull URL for broadcast $liveId');
  }

  // Links ---------------------------------------------------------------------

  /// The uid of an Inke room or app share link (see
  /// [InkeApi.roomIdFromUri]). The site has no short links.
  @override
  String? roomIdFromUrl(String url) => InkeApi.roomIdFromUri(Uri.tryParse(url.trim()));
}
