import 'dart:convert';
import 'dart:math';

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/twitch/twitch_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'twitch';

/// Continuation cursors kept (the oldest is dropped first).
const _cursorLimit = 256;

/// Pages of one category tag at most (30 directories each). 3.x had no
/// bound; a cursor that repeats also ends a tag.
const _tagPageLimit = 50;

final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');

/// Hosts whose first path segment is a channel.
const Set<String> _channelHosts = {'twitch.tv', 'www.twitch.tv', 'm.twitch.tv', 'go.twitch.tv'};

/// First path segments of Twitch's own pages, besides
/// [RoomPaths.reservedSegments].
const Set<String> _sitePages = {
  'drops',
  'following',
  'friends',
  'inventory',
  'jobs',
  'messages',
  'moderator',
  'p',
  'payments',
  'popout',
  'prime',
  'store',
  'subscriptions',
  'turbo',
  'wallet',
};

/// Channel logins as links spell them (3.x kept the case).
final RegExp _linkLogin = RegExp(r'^[a-zA-Z0-9_]{1,25}$');

/// The Twitch adapter (3.x's `TwitchSite`; parsing in [TwitchApi]).
///
/// Every request is anonymous except the playback access token, which
/// carries the stored session when there is one. Later pages of a list end
/// it quietly where Twitch asks for a browser's integrity token. Failures
/// are `SiteError`s; nothing is disguised as an offline room.
///
/// **GraphQL transports.** A GraphQL request goes to [http] first. When
/// that transport fails (a `TransportFailure` other than cancellation, or
/// HTTP 5xx) or Twitch answers with an integrity challenge, the same
/// request is sent through each of [gqlFallbacks] in order, and the first
/// answer that is neither is used. 3.x did this on Android (the system TLS
/// stack, then a headless WebView), because some proxies reset `dart:io`'s
/// TLS connection after CONNECT; the app injects those transports (M12),
/// see docs/modules/M4.08-twitch.md. A fallback gets exactly the
/// [LiveRequest] [http] got: `site` `twitch` (so the app's proxy route
/// applies), `POST https://gql.twitch.tv/gql`, lower-case headers, a JSON
/// body, the request's timeout and cancellation. It returns the real status
/// and the decoded body, and throws `TransportFailure` when no answer
/// arrived. Only `gql.twitch.tv` is ever sent through a fallback; usher and
/// media go through [http] and the player.
final class TwitchSite extends LiveSite
    with LiveSiteLinks
    implements LiveSiteRoomRefresher, LiveSiteRecordRoomResolver, LivePlayUrlResolver, LivePlayRecoveryResolver {
  /// Creates the adapter. [_cookies] holds the user's Twitch cookie, if
  /// any; [gqlFallbacks] are the extra GraphQL transports described above.
  /// [searchPaging] turns on the channel cursor for search pages after the
  /// first (see [searchRooms]). [random] (the `Device-Id`, the usher nonce)
  /// and [now] (the covers' `?&t=`) are injectable for tests.
  new(
    this.http, {
    this._cookies,
    Iterable<LiveHttp> gqlFallbacks = const [],
    this.searchPaging = false,
    Random? random,
    DateTime Function()? now,
  }) : gqlFallbacks = List.unmodifiable(gqlFallbacks),
       _random = random ?? Random.secure(),
       _now = now ?? DateTime.now;

  /// Transport of every request.
  final LiveHttp http;

  /// GraphQL transports tried after [http], in order.
  final List<LiveHttp> gqlFallbacks;

  /// Whether search pages after the first follow the channel cursor.
  final bool searchPaging;

  final CookieVault? _cookies;
  final Random _random;
  final DateTime Function() _now;

  /// `Device-Id` of every GraphQL and usher request, one per adapter.
  late final String _deviceId = TwitchApi.deviceId(_random);

  /// The cursor of each continuation page, by `list|id|…|page`.
  final Map<String, String> _cursors = {};

  /// The stored cookie Twitch refused for the access token; anonymous
  /// tokens are used until the cookie changes.
  String? _rejectedSession;

  @override
  String get id => _site;

  @override
  String get name => 'Twitch';

  // Requests ------------------------------------------------------------------

  /// The user's cookie ('' when signed out), control characters removed.
  String _session() => (_cookies?.cookieFor(_site) ?? '').replaceAll(_controlCharacters, '').trim();

  TwitchChatLogin? _chat() => TwitchApi.chatLogin(_session());

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  /// One GraphQL request of [operation] (an operation or a batch), decoded;
  /// [session] adds the stored cookie and its OAuth token. The transports
  /// are tried in order as the class describes; the last failure is
  /// reported.
  Future<Object> _gql(Object operation, {required String what, String session = ''}) async {
    final request = LiveRequest(
      site: _site,
      url: TwitchApi.gqlUrl,
      method: 'POST',
      headers: TwitchApi.gqlHeaders(deviceId: _deviceId, cookie: session),
      body: utf8.encode(jsonEncode(operation)),
    );
    SiteError? failure;
    for (final transport in [http, ...gqlFallbacks]) {
      try {
        final response = await transport.send(request);
        return TwitchApi.decode(response.text, status: response.status, what: what);
      } on TransportFailure catch (error) {
        if (error.reason == TransportReason.cancelled) rethrow;
        failure = NetworkFailure(_site, '$what: $error');
      } on RiskControl catch (error) {
        failure = error;
      } on NetworkFailure catch (error) {
        failure = error;
      }
    }
    throw failure!;
  }

  /// Remembers the cursor of continuation page [key], or forgets it at the
  /// end of a list.
  void _remember(String key, String? cursor) {
    _cursors.remove(key);
    if (cursor == null) return;
    _cursors[key] = cursor;
    if (_cursors.length > _cursorLimit) _cursors.remove(_cursors.keys.first);
  }

  // Catalog and search --------------------------------------------------------

  /// The category tags with their directories, as 3.x's `getCategores`:
  /// 30 directories a page, and a tag's next page while its last one was
  /// full and had a cursor. The pages of a round go out together, in
  /// batches of at most 35 operations. A failed first round fails the
  /// catalog; a failed later round ends those tags with the pages they have
  /// (3.x kept them too): anonymous clients are asked for an integrity token
  /// there.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    final tags = TwitchApi.tags(await _gql(TwitchApi.tagsOperation(), what: 'SearchCategoryTags'));
    final areas = {for (final tag in tags) tag.id: <LiveArea>[]};
    final seen = <String>{};
    var pages = [for (final tag in tags) (tag: tag, cursor: null as String?)];
    for (var round = 0; pages.isNotEmpty && round < _tagPageLimit; round++) {
      final answers = await _directoryRound(pages, lenient: round > 0);
      pages = [];
      for (final answer in answers) {
        areas[answer.tag.id]!.addAll(answer.areas);
        final cursor = answer.cursor;
        if (answer.areas.length >= TwitchApi.tagDirectoryLimit &&
            cursor != null &&
            seen.add('${answer.tag.id}|$cursor')) {
          pages.add((tag: answer.tag, cursor: cursor));
        }
      }
    }
    return [for (final tag in tags) LiveCategory(id: tag.id, name: tag.name, children: areas[tag.id]!)];
  }

  /// One page of directories for each of [pages], in batches of at most 35
  /// operations sent together. With [lenient] a failed batch just gives no
  /// pages.
  Future<List<({TwitchTag tag, List<LiveArea> areas, String? cursor})>> _directoryRound(
    List<({TwitchTag tag, String? cursor})> pages, {
    required bool lenient,
  }) async {
    final chunks = [
      for (var start = 0; start < pages.length; start += TwitchApi.batchLimit)
        pages.sublist(start, min(start + TwitchApi.batchLimit, pages.length)),
    ];
    Future<List<({TwitchTag tag, List<LiveArea> areas, String? cursor})>> ask(
      List<({TwitchTag tag, String? cursor})> chunk,
    ) async {
      const what = 'BrowsePage_AllDirectories';
      try {
        final answer = await _gql([
          for (final page in chunk) TwitchApi.directoriesOperation(page.tag.id, cursor: page.cursor),
        ], what: what);
        return [
          for (final (index, envelope) in TwitchApi.batch(answer, expected: chunk.length, what: what).indexed)
            if (TwitchApi.directories(envelope, chunk[index].tag) case (:final areas, :final cursor))
              (tag: chunk[index].tag, areas: areas, cursor: cursor),
        ];
      } on SiteError {
        if (lenient) return const [];
        rethrow;
      }
    }

    return [
      for (final answers in await Future.wait([for (final chunk in chunks) ask(chunk)])) ...answers,
    ];
  }

  /// The streams of the directory `category.shortName` (its slug). An area
  /// without one has no streams, without a request (3.x asked for an empty
  /// slug and got none).
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final slug = category.shortName.trim();
    if (slug.isEmpty) return const [];
    return await _directory('area', slug, page: page, pageSize: pageSize);
  }

  /// The Just Chatting directory, as in 3.x.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) =>
      _directory('recommend', TwitchApi.recommendSlug, page: page, pageSize: pageSize);

  /// Page [page] of a directory's streams, [pageSize] (1–100) at a time.
  /// A later page continues from the cursor the page before left; without
  /// one the list has ended. A later page answered with an integrity
  /// challenge ends the list too: the first page is what an anonymous
  /// client gets.
  Future<List<LiveRoom>> _directory(String list, String slug, {required int page, required int pageSize}) async {
    final number = page < 1 ? 1 : page;
    final limit = pageSize.clamp(1, 100);
    final key = '$list|$slug|$limit';
    final cursor = number == 1 ? null : _cursors['$key|$number'];
    if (number > 1 && cursor == null) return const [];
    final Object answer;
    try {
      answer = await _gql([TwitchApi.gameOperation(slug, limit: limit, cursor: cursor)], what: 'DirectoryPage_Game');
    } on RiskControl {
      if (cursor != null) return const [];
      rethrow;
    }
    final result = TwitchApi.gameStreams(answer, now: _now(), chat: _chat());
    _remember('$key|${number + 1}', result.cursor);
    return result.rooms;
  }

  /// Channels matching [keyword], live or not. A blank keyword gives
  /// nothing without a request.
  ///
  /// Later pages are empty without a request unless [searchPaging] is on:
  /// 3.x sent the cursor where the server ignores it, so its page 2
  /// repeated page 1 and the search page stopped there. Users saw the first
  /// page; on, later pages follow the channel cursor in `options.targets`.
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final number = page < 1 ? 1 : page;
    final key = 'search|$text';
    final cursor = number == 1 || !searchPaging ? null : _cursors['$key|$number'];
    if (number > 1 && cursor == null) return const [];
    final Object answer;
    try {
      answer = await _gql(TwitchApi.searchOperation(text, cursor: cursor), what: 'SearchResultsPage_SearchResults');
    } on RiskControl {
      if (cursor != null) return const [];
      rethrow;
    }
    final result = TwitchApi.searchPage(answer, now: _now(), chat: _chat());
    _remember('$key|${number + 1}', result.cursor);
    return result.rooms;
  }

  // Rooms ---------------------------------------------------------------------

  /// The channel [roomId] (a login in any case; the requests use it lower
  /// case, the room keeps it as asked). Not a login is `NotFound` without a
  /// request.
  Future<LiveRoom> _detail(String roomId) async {
    final id = roomId.trim();
    final login = id.toLowerCase();
    if (!TwitchApi.loginPattern.hasMatch(login)) throw NotFound(_site, 'not a channel login: $id');
    final answer = await _gql(TwitchApi.userOperation(login), what: 'user');
    return TwitchApi.roomDetail(answer, requestedId: id, chat: _chat());
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  /// The same query as room entry: it is one small request.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  /// Whether the detail says live; a failed request is an error, never
  /// "offline".
  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _detail(roomId)).isLiveNow;

  // Streams -------------------------------------------------------------------

  /// The variants of the master playlist. A room the detail did not call
  /// live has none: `StreamUnavailable` without a request (3.x returned no
  /// qualities).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    if (!detail.isLiveNow) throw StreamUnavailable(_site, '${detail.roomId}: not live');
    return await _qualities(detail.roomId);
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The variant URLs [quality] carries, as lines; a quality without them
  /// (restored from elsewhere) gets a fresh playlist.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final urls = [
      for (final url in switch (quality.data) {
        final List<Object?> list => list,
        _ => const <Object?>[],
      })
        if ('${url ?? ''}'.trim() case final text when text.isNotEmpty) text,
    ];
    if (urls.isEmpty) return await _fresh(detail, quality);
    return TwitchApi.resolution(
      urls,
      roomId: detail.roomId,
      appliedQualityData: quality.selectionId,
      cookie: _session(),
    );
  }

  /// A new access token and master playlist: the variant URLs of a playlist
  /// fetched long ago may have expired.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _fresh(detail, quality);

  /// [quality] from a new playlist: the same variant (by id, `VIDEO` group
  /// or label), else the first (the source).
  Future<LivePlayUrlResolution> _fresh(LiveRoom detail, LivePlayQuality quality) async {
    final qualities = await _qualities(detail.roomId);
    final same = TwitchApi.sameQuality(qualities, quality);
    final chosen = same ?? qualities.first;
    return TwitchApi.resolution(
      chosen.data! as List<String>,
      roomId: detail.roomId,
      appliedQualityData: same == null ? chosen.selectionId : quality.selectionId,
      cookie: _session(),
    );
  }

  /// The access token, then usher's master playlist, as qualities.
  Future<List<LivePlayQuality>> _qualities(String roomId) async {
    final login = roomId.trim().toLowerCase();
    if (!TwitchApi.loginPattern.hasMatch(login)) throw NotFound(_site, 'not a channel login: $roomId');
    final token = await _accessToken(login);
    final url = TwitchApi.usherUrl(login, token, _random);
    final response = await _send(
      LiveRequest(
        site: _site,
        url: url,
        headers: TwitchApi.usherHeaders(deviceId: _deviceId),
      ),
    );
    TwitchApi.usherStatus(response.status, response.text);
    return TwitchApi.qualities(response.text, master: url);
  }

  /// `PlaybackAccessToken`, with the stored session when there is one (a
  /// subscriber's or Turbo token). When Twitch refuses the session (HTTP
  /// 401 or an integrity challenge) the token is requested anonymously, and
  /// that cookie is not sent again until it changes (3.x's
  /// `_bypassStoredSessionForIntegrity`).
  Future<TwitchAccessToken> _accessToken(String login) async {
    final operation = TwitchApi.accessTokenOperation(login);
    final session = _session();
    if (session.isNotEmpty && session != _rejectedSession) {
      Object? answer;
      try {
        answer = await _gql(operation, what: 'PlaybackAccessToken', session: session);
      } on NeedsLogin {
        _rejectedSession = session;
      } on RiskControl {
        _rejectedSession = session;
      }
      if (answer != null) return TwitchApi.accessToken(answer, login: login);
    }
    return TwitchApi.accessToken(await _gql(operation, what: 'PlaybackAccessToken'), login: login);
  }

  // Links ---------------------------------------------------------------------

  /// A channel page of `twitch.tv` (`www`, `m`, `go`: the first path
  /// segment), a pop-out chat (`/popout/<login>/chat`) or the embedded
  /// player (`player.twitch.tv/?channel=<login>`). The login keeps the case
  /// it was written in, as in 3.x; Twitch's own pages are not channels.
  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !ShortLinkSession.isHttpUri(uri)) return null;
    final host = uri.host.toLowerCase();
    try {
      if (host == 'player.twitch.tv') return _channel(uri.queryParameters['channel']?.trim() ?? '');
      if (!_channelHosts.contains(host)) return null;
      final segments = RoomPaths.segments(uri);
      if (segments.isEmpty) return null;
      final popout = segments.first.toLowerCase() == 'popout' && segments.length >= 2;
      return _channel((popout ? segments[1] : segments.first).trim());
    } on FormatException {
      return null;
    }
  }

  static String? _channel(String segment) =>
      RoomPaths.isRoomIdentifier(segment, _linkLogin) && !_sitePages.contains(segment.toLowerCase()) ? segment : null;
}
