import 'dart:async';
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

/// List snapshots kept (the oldest is dropped first).
const _snapshotLimit = 16;

/// How long a list snapshot serves the pages after the first (the unified
/// paging rule: 20–30 s). The first page always fetches a new one.
const _snapshotLifetime = Duration(seconds: 30);

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

/// One list's streams as fetched so far, paged locally: the rooms in the
/// server's order (each once), the cursor of the next chunk, when the first
/// chunk arrived and where each page served so far ended.
final class _Snapshot {
  new(this.fetchedAt);

  final DateTime fetchedAt;
  final List<LiveRoom> rooms = [];
  final Set<String> _ids = {};
  String? cursor;

  /// The first room of each page after one already served, by page number.
  final Map<int, int> starts = {};

  /// Adds a chunk; a chunk that brings no new room ends the list (a cursor
  /// that goes nowhere must not be followed forever).
  void add(({List<LiveRoom> rooms, String? cursor}) chunk) {
    var added = false;
    for (final room in chunk.rooms) {
      if (_ids.add(room.identityKey)) {
        rooms.add(room);
        added = true;
      }
    }
    cursor = added ? chunk.cursor : null;
  }
}

/// The Twitch adapter (3.x's `TwitchSite`; parsing in [TwitchApi]).
///
/// Every request is anonymous except the playback access token, which
/// carries the stored session when there is one. Later pages of a list end
/// it quietly where Twitch asks for a browser's integrity token. Failures
/// are `SiteError`s; nothing is disguised as an offline room.
///
/// **Lists.** Names are Chinese (`Accept-Language: zh-CN`). An area's
/// streams are fetched 100 at a time and the recommendations (the site's
/// busiest streams) 30 at a time; pages of any size are cut from that
/// snapshot, each where the one before ended, and a page that would start
/// past its end fetches the next chunk from the cursor. The first page
/// always fetches anew; later pages use the snapshot while it is under 30 s
/// old. Both lists keep only the broadcast languages of the "Twitch 语言筛选"
/// setting when it gives any (3.x: always Chinese and Korean,
/// [TwitchApi.legacyLanguages]). Search follows the channel cursor.
///
/// **GraphQL transports.** A GraphQL request goes to [http] first. When
/// that transport fails (a `TransportFailure` other than cancellation, or
/// HTTP 5xx) or Twitch answers with an integrity challenge, the same
/// request is sent through each of [gqlFallbacks] in order, and the first
/// answer that is neither is used. 3.x did this on Android (the system TLS
/// stack, then a headless WebView), because some proxies reset `dart:io`'s
/// TLS connection after CONNECT; the app injects those transports (M12),
/// see docs/T02/T02c/T02c.2/record.md. A fallback gets exactly the
/// [LiveRequest] [http] got: `site` `twitch` (so the app's proxy route
/// applies), `POST https://gql.twitch.tv/gql`, lower-case headers, a JSON
/// body, the request's timeout and cancellation. It returns the real status
/// and the decoded body, and throws `TransportFailure` when no answer
/// arrived. Only `gql.twitch.tv` is ever sent through a fallback; usher and
/// media go through [http] and the player.
final class TwitchSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver,
        LiveSiteCookieRefusals {
  /// Creates the adapter. [_cookies] holds the user's Twitch cookie, if
  /// any; [gqlFallbacks] are the extra GraphQL transports described above.
  /// The settings are read at each request, so a change needs no new
  /// adapter:
  /// - [languages] reads "Twitch 语言筛选" (`twitchLanguages`): the broadcast
  ///   languages the area pages and the recommendations keep (Twitch codes
  ///   such as `ZH`, `KO`; see [TwitchApi.normalizeLanguages]); none, the
  ///   default, keeps every language;
  /// - [preferH264] reads "优先 H.264" (on by default): on, usher is asked
  ///   for H.264 only; off, also for HEVC and AV1 (Enhanced Broadcasting),
  ///   as far as [codecs] says the player decodes them;
  /// - [codecs] reads the video codecs the player's engine decodes, named
  ///   as lines name them (`avc`, `hevc`, `av1`); null (the default) is not
  ///   known, and every codec is asked for (8-8).
  ///
  /// [random] (the `Device-Id`, the usher nonce) and [now] (the covers'
  /// `?&t=`, the snapshots' age) are injectable for tests.
  new(
    this.http, {
    this._cookies,
    Iterable<LiveHttp> gqlFallbacks = const [],
    List<String> Function()? languages,
    bool Function()? preferH264,
    Set<String>? Function()? codecs,
    Random? random,
    DateTime Function()? now,
  }) : gqlFallbacks = List.unmodifiable(gqlFallbacks),
       _languages = languages ?? _everyLanguage,
       _preferH264 = preferH264 ?? _on,
       _codecs = codecs ?? _unknownCodecs,
       _random = random ?? Random.secure(),
       _now = now ?? DateTime.now;

  /// Transport of every request.
  final LiveHttp http;

  /// GraphQL transports tried after [http], in order.
  final List<LiveHttp> gqlFallbacks;

  final CookieVault? _cookies;
  final List<String> Function() _languages;
  final bool Function() _preferH264;
  final Set<String>? Function() _codecs;
  final Random _random;
  final DateTime Function() _now;

  static List<String> _everyLanguage() => const [];

  static bool _on() => true;

  static Set<String>? _unknownCodecs() => null;

  /// `Device-Id` of every GraphQL and usher request, one per adapter.
  late final String _deviceId = TwitchApi.deviceId(_random);

  /// The cursor of each search page after the first, by `search|keyword|page`.
  final Map<String, String> _cursors = {};

  /// The area and recommendation snapshots, by list and languages.
  final Map<String, _Snapshot> _snapshots = {};

  /// The stored cookie Twitch refused for the access token; anonymous
  /// tokens are used until the cookie changes.
  String? _rejectedSession;

  final StreamController<void> _refusals = StreamController<void>.broadcast();

  /// An event when Twitch refuses the stored cookie for the access token
  /// (B-7): playback carries on anonymously and that cookie is not sent
  /// again until it changes, so each cookie is reported once. The chat
  /// says the same in its own notice (`TwitchDanmakuProtocol.cookieExpiredNotice`).
  @override
  Stream<void> get cookieRefusals => _refusals.stream;

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
  /// [session] adds the stored cookie and its OAuth token, [language] is
  /// the `Accept-Language`. The transports are tried in order as the class
  /// describes; the last failure is reported.
  Future<Object> _gql(
    Object operation, {
    required String what,
    String session = '',
    String language = TwitchApi.acceptLanguage,
  }) async {
    final request = LiveRequest(
      site: _site,
      url: TwitchApi.gqlUrl,
      method: 'POST',
      headers: TwitchApi.gqlHeaders(deviceId: _deviceId, cookie: session, language: language),
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
  /// there. Names are Chinese; the tags Twitch has no Chinese name for get
  /// their English one from one more tags request (8-2).
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    var tags = TwitchApi.tags(await _gql(TwitchApi.tagsOperation(), what: 'SearchCategoryTags'));
    if (tags.any((tag) => tag.name.isEmpty)) tags = await _namedTags(tags);
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

  /// [tags] with English names for those without a Chinese one. The names
  /// are cosmetic: when that request fails the tags keep their empty names.
  Future<List<TwitchTag>> _namedTags(List<TwitchTag> tags) async {
    try {
      final english = await _gql(
        TwitchApi.tagsOperation(),
        what: 'SearchCategoryTags (en)',
        language: TwitchApi.englishLanguage,
      );
      return TwitchApi.namedTags(tags, TwitchApi.tags(english));
    } on SiteError {
      return tags;
    }
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

  /// The streams of the directory `category.shortName` (its slug), fetched
  /// 100 at a time and paged locally (8-10), in the chosen languages (8-3).
  /// An unknown directory is `NotFound` (8-6). An area without a slug has
  /// no streams, without a request (3.x asked for an empty slug and got
  /// none).
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final slug = category.shortName.trim();
    if (slug.isEmpty) return const [];
    final languages = _chosenLanguages();
    return await _page('area|$slug|${languages.join(',')}', page: page, pageSize: pageSize, (cursor) async {
      final answer = await _gql([
        TwitchApi.gameOperation(slug, limit: TwitchApi.directoryFetchLimit, cursor: cursor, languages: languages),
      ], what: 'DirectoryPage_Game');
      return TwitchApi.gameStreams(answer, now: _now(), chat: _chat(), slug: slug);
    });
  }

  /// The busiest live streams of the whole site (8-3; 3.x: the Just
  /// Chatting directory), in the chosen languages, 30 at a time (the most
  /// Twitch gives) and paged locally.
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    final languages = _chosenLanguages();
    return await _page('recommend|${languages.join(',')}', page: page, pageSize: pageSize, (cursor) async {
      final answer = await _gql(
        TwitchApi.streamsOperation(limit: TwitchApi.streamsLimit, cursor: cursor, languages: languages),
        what: 'streams',
      );
      return TwitchApi.streams(answer, now: _now(), chat: _chat());
    });
  }

  /// The broadcast languages of the setting, as Twitch spells them.
  List<String> _chosenLanguages() => TwitchApi.normalizeLanguages(_languages());

  /// Page [page] of the list [key]: up to [pageSize] (1–100) rooms cut from
  /// its snapshot, starting where the page before ended.
  /// - The first page fetches a new snapshot with [fetch]; a later one does
  ///   when the snapshot is missing or 30 s old.
  /// - Only a page that would start past the snapshot's end fetches the next
  ///   chunk from its cursor, so a page may hold fewer rooms than asked; an
  ///   empty page is the end. (Filling every page would cost the
  ///   recommendations a second request each time: Twitch often gives 29
  ///   of the 30 asked for.)
  /// - A chunk answered with an integrity challenge ends the list quietly
  ///   (anonymous clients get the first chunk only); other failures fail
  ///   the page and keep the cursor.
  Future<List<LiveRoom>> _page(
    String key,
    Future<({List<LiveRoom> rooms, String? cursor})> Function(String? cursor) fetch, {
    required int page,
    required int pageSize,
  }) async {
    final number = page < 1 ? 1 : page;
    final size = pageSize.clamp(1, 100);
    var snapshot = _snapshots[key];
    final now = _now();
    if (number == 1 || snapshot == null || now.difference(snapshot.fetchedAt) >= _snapshotLifetime) {
      final fresh = _Snapshot(now)..add(await fetch(null));
      _snapshots
        ..remove(key)
        ..[key] = fresh;
      if (_snapshots.length > _snapshotLimit) _snapshots.remove(_snapshots.keys.first);
      snapshot = fresh;
    }
    final start = number == 1 ? 0 : snapshot.starts[number] ?? (number - 1) * size;
    while (start >= snapshot.rooms.length && snapshot.cursor != null) {
      try {
        snapshot.add(await fetch(snapshot.cursor));
      } on RiskControl {
        snapshot.cursor = null;
      }
    }
    final rooms = snapshot.rooms;
    if (start >= rooms.length) return const [];
    final end = min(start + size, rooms.length);
    snapshot.starts[number + 1] = end;
    return List.unmodifiable(rooms.sublist(start, end));
  }

  /// Channels matching [keyword], live or not, page by page along the
  /// channel cursor in `options.targets` (8-1; 3.x sent the cursor where
  /// the server ignores it, so its page 2 repeated page 1). A blank keyword
  /// gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final number = page < 1 ? 1 : page;
    final key = 'search|$text';
    final cursor = number == 1 ? null : _cursors['$key|$number'];
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
    return TwitchApi.roomDetail(answer, requestedId: id, now: _now(), chat: _chat());
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

  /// The variants of the master playlist, of a live stream or a rerun
  /// (8-9). A room the detail called offline has none: `StreamUnavailable`
  /// without a request (3.x returned no qualities).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    if (!detail.isPlayableNow) throw StreamUnavailable(_site, '${detail.roomId}: nothing on air');
    return await _qualities(detail);
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The variant URLs [quality] carries, as lines (with their codec when the
  /// quality came from [getPlayQualities]); a quality without them
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
      codec: _codec(quality),
    );
  }

  static String? _codec(LivePlayQuality quality) => switch (quality.data) {
    TwitchVariants(:final codec) => codec,
    _ => null,
  };

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
    final qualities = await _qualities(detail);
    final same = TwitchApi.sameQuality(qualities, quality);
    final chosen = same ?? qualities.first;
    return TwitchApi.resolution(
      chosen.data! as List<String>,
      roomId: detail.roomId,
      appliedQualityData: same == null ? chosen.selectionId : quality.selectionId,
      codec: _codec(chosen),
    );
  }

  /// The access token, then usher's master playlist (asking for the codecs
  /// the "优先 H.264" setting and the engine allow, 8-8), as qualities. When the detail
  /// marked the stream restricted and Twitch refuses this viewer (a
  /// forbidden token or usher 403 that is not about the region), the
  /// refusal is `StreamUnavailable` naming the restriction.
  Future<List<LivePlayQuality>> _qualities(LiveRoom detail) async {
    final login = detail.roomId.trim().toLowerCase();
    if (!TwitchApi.loginPattern.hasMatch(login)) throw NotFound(_site, 'not a channel login: ${detail.roomId}');
    try {
      final token = await _accessToken(login);
      final url = TwitchApi.usherUrl(login, token, _random, preferH264: _preferH264(), codecs: _codecs());
      final response = await _send(
        LiveRequest(
          site: _site,
          url: url,
          headers: TwitchApi.usherHeaders(deviceId: _deviceId),
        ),
      );
      TwitchApi.usherStatus(response.status, response.text);
      return TwitchApi.qualities(response.text, master: url);
    } on NeedsLogin catch (error) {
      if (!detail.isRestricted) rethrow;
      throw StreamUnavailable(_site, 'restricted stream (${detail.effectiveRestriction.name}): ${error.detail ?? ''}');
    }
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
        _refuse(session);
      } on RiskControl {
        _refuse(session);
      }
      if (answer != null) return TwitchApi.accessToken(answer, login: login);
    }
    return TwitchApi.accessToken(await _gql(operation, what: 'PlaybackAccessToken'), login: login);
  }

  void _refuse(String session) {
    _rejectedSession = session;
    _refusals.add(null);
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
