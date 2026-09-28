import 'dart:async';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/chzzk/chzzk_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'chzzk';

/// The CHZZK (치지직) adapter (3.x's `ChzzkSite`; parsing in [ChzzkApi]).
///
/// A room is a channel, its id the 32-hex `channelId`, as 3.x stored it.
/// Anonymous, like 3.x: no cookie, no account; every request carries
/// [ChzzkApi.headers] and follows no redirect. Requests are 3.x's:
/// - the catalog is one fixed area, the popular directory, without a
///   request;
/// - the directory is `/service/v1/lives`, one request a page by cursor
///   ([getDirectoryPageAtCursor]); by page number ([getDirectoryPage],
///   recommendations and the area) it replays from page 1, within 20
///   seconds;
/// - search is `/service/v1/search/channels`, one request a page;
/// - follow refreshes and the live state read the channel and its
///   `v3.1 live-detail` (two requests);
/// - room entry, recordings and recovery read both, then each HLS master
///   of the live (four requests for a playable live).
///
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class ChzzkSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LiveSiteCursorDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter. [now] (when masters were issued) and
  /// `directoryDeadline` (3.x's 20 seconds for a page-number replay) are
  /// injectable for tests.
  new(this.http, {DateTime Function()? now, this._directoryDeadline = const Duration(seconds: 20)})
    : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;
  final Duration _directoryDeadline;

  @override
  String get id => _site;

  @override
  String get name => ChzzkApi.categoryName;

  /// 3.x's lasting note on what the directory covers (the site-wide popular
  /// lives; search also finds offline channels).
  @override
  String get directoryNoticeKey => 'chzzk_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A GET of [url] with 3.x's headers, redirects not followed (as 3.x). A
  /// cancellation before the request or while it runs is a cancelled
  /// `TransportFailure`, also when the answer (or a transport failure)
  /// arrived meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _get(Uri url, {CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(
        LiveRequest(site: _site, url: url, headers: ChzzkApi.headers, followRedirects: false, cancel: cancel),
      );
      _checkCancelled(cancel);
      return response;
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      _checkCancelled(cancel);
      throw NetworkFailure(_site, failure.toString());
    }
  }

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  static Uri _api(String path, [Map<String, String>? query]) => Uri.https(ChzzkApi.apiHost, path, query);

  // Catalog and directory -----------------------------------------------------

  /// 3.x's catalog (see [ChzzkApi.categories]) on page 1; later pages are
  /// empty. No request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async =>
      page == 1 ? ChzzkApi.categories() : const [];

  /// The directory page after [cursor] (null on page 1): one request (see
  /// [ChzzkApi.livesQuery] and [ChzzkApi.lives]). [page] is the caller's
  /// sequence: page 1 takes no cursor and later pages need one; [category]
  /// is null or the popular area. Anything else, or a cursor this adapter
  /// did not make, is a caller error (`ArgumentError`), refused before any
  /// request as in 3.x.
  @override
  Future<LiveDirectoryPage> getDirectoryPageAtCursor({
    required int page,
    String? cursor,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    if ((page == 1) != (cursor == null)) {
      throw ArgumentError.value(cursor, 'cursor', page == 1 ? 'page 1 takes no cursor' : 'page $page needs a cursor');
    }
    ChzzkApi.checkArea(category);
    final response = await _get(_api('/service/v1/lives', ChzzkApi.livesQuery(cursor)), cancel: cancel);
    final result = ChzzkApi.lives(response.text, cursor: cursor, status: response.status);
    return LiveDirectoryPage(rooms: result.rooms, page: page, hasMore: result.hasMore, nextCursor: result.nextCursor);
  }

  /// Page [page] (1–20) of the directory, replayed from page 1 by cursor (3.x:
  /// [page] requests); a directory that ends first gives an empty last page.
  /// The replay has [ChzzkSite.new]'s deadline (20 seconds), after which its
  /// requests are cancelled and it is a `NetworkFailure`.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1 || page > ChzzkApi.maxDirectoryPage) {
      throw RangeError.range(page, 1, ChzzkApi.maxDirectoryPage, 'page');
    }
    ChzzkApi.checkArea(category);
    final owned = CancelToken();
    if (cancel != null) {
      if (cancel.isCancelled) owned.cancel();
      unawaited(cancel.whenCancelled.then((_) => owned.cancel()));
    }
    Future<LiveDirectoryPage> replay() async {
      String? cursor;
      for (var current = 1; ; current++) {
        final result = await getDirectoryPageAtCursor(page: current, cursor: cursor, category: category, cancel: owned);
        if (current == page) return result;
        if (!result.hasMore) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
        cursor = result.nextCursor;
      }
    }

    try {
      return await replay().timeout(
        _directoryDeadline,
        onTimeout: () => throw NetworkFailure(_site, 'directory page $page: over $_directoryDeadline'),
      );
    } finally {
      owned.cancel();
    }
  }

  /// Page [page] of the popular directory ([getDirectoryPage]); [pageSize]
  /// is not sent (3.x).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await getDirectoryPage(page: page)).rooms;

  /// As [getRecommendRooms], for the popular area.
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      (await getDirectoryPage(page: page, category: category)).rooms;

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Channels matching [keyword], live and offline (see
  /// [ChzzkApi.searchRooms]), [pageSize] a page from offset
  /// `(page - 1) * pageSize`. As 3.x, a page below 1 or a [pageSize] out of
  /// 1–30 finds nothing, without a request. A blank keyword finds nothing
  /// too (3.x refused it); a keyword over 100 characters or an offset over
  /// 1000000 is a caller error (`ArgumentError`, no request), as 3.x
  /// refused them.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page < 1 || pageSize < 1 || pageSize > ChzzkApi.maxSearchPageSize) return const [];
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    if (text.length > ChzzkApi.maxKeywordLength) {
      throw ArgumentError.value(keyword, 'keyword', 'over ${ChzzkApi.maxKeywordLength} characters');
    }
    final offset = (page - 1) * pageSize;
    if (offset > ChzzkApi.maxSearchOffset) throw RangeError.range(offset, 0, ChzzkApi.maxSearchOffset, 'offset');
    final response = await _get(
      _api('/service/v1/search/channels', {'keyword': text, 'offset': '$offset', 'size': '$pageSize'}),
      cancel: cancel,
    );
    return ChzzkApi.searchRooms(response.text, status: response.status);
  }

  // Rooms ---------------------------------------------------------------------

  /// The channel and its latest live (two requests); an id that is not a
  /// channel id (32 lower-case hex digits, as 3.x checked) is `NotFound`
  /// without a request.
  Future<({ChzzkChannel owner, ChzzkLive? live})> _read(String roomId) async {
    final id = roomId.trim();
    if (!ChzzkApi.isChannelId(id)) throw NotFound(_site, 'not a channel id: $id');
    final channel = await _get(_api('/service/v1/channels/$id'));
    final owner = ChzzkApi.channel(channel.text, channelId: id, status: channel.status);
    final live = await _get(_api('/service/v3.1/channels/$id/live-detail'));
    return (owner: owner, live: ChzzkApi.liveDetail(live.text, owner: owner, status: live.status));
  }

  /// Room entry (3.x's `_detail` with playback): the channel, its live, and
  /// for an open live with playback data each HLS master in order, which
  /// give the qualities ([ChzzkRoomData]). A master that fails, or cannot be
  /// read, fails the entry as in 3.x. A live without playback data (region,
  /// adult) is entered; its stream says why it cannot play.
  Future<LiveRoom> _entered(String roomId, {bool withDanmaku = false}) async {
    final (:owner, :live) = await _read(roomId);
    final room = ChzzkApi.room(owner, live);
    final chat = live != null && live.isLive ? live.chatChannelId : null;
    return room.copyWith(
      data: await _playback(owner.id, live),
      danmakuData: withDanmaku && chat != null ? ChzzkDanmakuArgs(chatChannelId: chat) : null,
    );
  }

  Future<ChzzkRoomData> _playback(String channelId, ChzzkLive? live) async {
    if (live?.mediaError case final error?) throw error;
    if (live == null || !live.isLive || live.media.isEmpty) {
      return ChzzkRoomData(channelId: channelId, unavailable: ChzzkApi.unavailable(live));
    }
    final masters = <({ChzzkMedia media, String body})>[];
    for (final media in live.media) {
      final response = await _get(media.url);
      masters.add((
        media: media,
        body: ChzzkApi.master(response.text, what: '${media.id} master', status: response.status),
      ));
    }
    return ChzzkRoomData(
      channelId: channelId,
      qualities: ChzzkApi.qualities(masters, issuedAt: _now()),
    );
  }

  /// The room with its qualities and the live's chat channel.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _entered(roomId, withDanmaku: true);

  /// Follow-card refresh: the channel and its live, two requests as in 3.x;
  /// no masters.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async {
    final (:owner, :live) = await _read(roomId);
    return ChzzkApi.room(owner, live);
  }

  /// Room entry's answer (the qualities included), as 3.x's recorder asked.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _entered(roomId);

  /// Whether the refresh detail says live; a failed request is an error,
  /// never "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// 3.x's qualities (see [ChzzkApi.qualities]) from the data room entry
  /// brought: no request. A room without it (a list card, a refreshed
  /// follow) is entered first; one the platform called offline has no
  /// stream (`StreamUnavailable`, without a request). A live that cannot be
  /// played says why (see [ChzzkApi.unavailable]).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      ChzzkApi.playQualities(await _stream(detail, fresh: false));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality]: `HLS` then `LLHLS`, with the media headers and
  /// their leases.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => ChzzkApi.resolution(await _stream(detail, fresh: false), quality);

  /// Room entry again (3.x): the masters carry tokens. A quality the live no
  /// longer offers is `StreamUnavailable`; the old lines are never reused.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => ChzzkApi.resolution(await _stream(detail, fresh: true), quality);

  Future<ChzzkRoomData> _stream(LiveRoom detail, {required bool fresh}) async {
    if (detail.platform != _site) throw ArgumentError.value(detail, 'detail', 'not a CHZZK room');
    if (!fresh) {
      if (detail.data case final ChzzkRoomData data when data.channelId == detail.roomId) return data;
      if (detail.isExplicitlyOfflineNow) {
        throw StreamUnavailable(_site, '${detail.roomId} is ${detail.effectiveLiveStatus.name}');
      }
    }
    return (await _entered(detail.roomId)).data! as ChzzkRoomData;
  }

  // Links ---------------------------------------------------------------------

  /// A live page `https://chzzk.naver.com/live/<id>` (see
  /// [ChzzkApi.roomIdFromUrl]), without a request. CHZZK has no short
  /// links.
  @override
  String? roomIdFromUrl(String url) => ChzzkApi.roomIdFromUrl(url);
}
