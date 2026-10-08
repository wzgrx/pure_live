import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/quality_label.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'twitch';

/// The chat login in a stored Twitch cookie: its `login` and `auth-token`.
typedef TwitchChatLogin = ({String login, String token});

/// `PlaybackAccessToken`: the token and its signature, the usher query's
/// `token` and `sig`.
typedef TwitchAccessToken = ({String value, String signature});

/// A category tag of `SearchCategoryTags`.
typedef TwitchTag = ({String id, String name});

/// What the danmaku connection needs to join one channel's chat: the
/// channel, and the chat login when the stored cookie holds both
/// `auth-token` and `login` (3.x's `TwitchDanmaku.joinRoom` read them from
/// the settings; otherwise it joined as an anonymous `justinfan` nick).
@immutable
final class TwitchDanmakuArgs {
  /// Creates the arguments.
  const new({required this.channel, this.chat});

  /// Channel login, lower case (`JOIN #<channel>`).
  final String channel;

  /// The user's chat login (`PASS oauth:<token>`, `NICK <login>`); null
  /// for an anonymous nick.
  final TwitchChatLogin? chat;

  /// The channel, as 3.x printed its danmaku data; never the token.
  @override
  String toString() => channel;
}

/// The `data` of a Twitch [LivePlayQuality]: its variant URLs, as 3.x kept
/// them, with the video codec the master playlist names for them (`avc`,
/// `hevc`, `av1`; null when it names none), so each line says what it holds.
final class TwitchVariants extends UnmodifiableListView<String> {
  /// The variant [urls] of one quality, encoded with [codec].
  new(Iterable<String> urls, {this.codec}) : super(List<String>.of(urls));

  /// Video codec of the variants, when the playlist names it.
  final String? codec;
}

/// Pure parsing of Twitch responses (3.x's `TwitchSite`). GraphQL answers
/// are decoded once by [decode], which also recognises the integrity
/// challenge; each parser takes that value and returns 3.x's models or
/// throws a `SiteError`.
abstract final class TwitchApi {
  /// Desktop Chrome 137, the UA 3.x sent to GraphQL, usher and the CDN.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/137.0.0.0 Safari/537.36';

  /// The web client's id.
  static const String clientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';

  /// The site, `Origin` of every request.
  static const String origin = 'https://www.twitch.tv';

  /// The GraphQL endpoint.
  static final Uri gqlUrl = Uri.https('gql.twitch.tv', '/gql');

  /// Operations one GraphQL request may carry (`BATCH_LIMIT_EXCEEDED`
  /// above).
  static const int batchLimit = 35;

  /// Directories per page of a category tag (3.x's page size).
  static const int tagDirectoryLimit = 30;

  /// Streams one `DirectoryPage_Game` request asks for: an area's list is
  /// fetched 100 at a time and paged locally (8-10), as 3.x's popular page
  /// did with its recommendations.
  static const int directoryFetchLimit = 100;

  /// Streams one site-wide `streams` request may ask for (`first` is 1–30).
  static const int streamsLimit = 30;

  /// `Accept-Language` of every request: Chinese names for category tags,
  /// directories and games (8-2; 3.x asked for en-US).
  static const String acceptLanguage = 'zh-CN,zh;q=0.9,en;q=0.8';

  /// `Accept-Language` of the one request for English tag names, for the
  /// tags Twitch has no Chinese name for.
  static const String englishLanguage = 'en-US,en;q=0.9';

  /// The broadcast languages 3.x always filtered the lists by (Chinese and
  /// Korean): the preset of the "Twitch 语言筛选" setting (8-3). The
  /// adapter filters by nothing unless given languages.
  static const List<String> legacyLanguages = ['ZH', 'KO'];

  /// A broadcast language as Twitch's `Language` enum spells it (`ZH`,
  /// `ZH_HK`, `ASL`, `OTHER`).
  static final RegExp languagePattern = RegExp(r'^[A-Z]{2,5}(_[A-Z]{2,4})?$');

  /// usher's `supported_codecs` when H.264 is preferred (8-8), as the web
  /// player names it.
  static const String h264Codecs = 'h264';

  /// usher's `supported_codecs` that also allows HEVC and AV1 (Enhanced
  /// Broadcasting), as the web player asks.
  static const String enhancedCodecs = 'av1,h265,h264';

  /// usher's `supported_codecs` (8-8): [h264Codecs] when [preferH264];
  /// otherwise the web player's [enhancedCodecs] limited to the video
  /// codecs the engine decodes, named as lines name them (`av1`, `hevc`;
  /// [codecs] null when not known: all of them). H.264 is always asked
  /// for, last, as the web player does.
  static String supportedCodecs({required bool preferH264, Set<String>? codecs}) {
    if (preferH264) return h264Codecs;
    return [
      if (codecs == null || codecs.contains('av1')) 'av1',
      if (codecs == null || codecs.contains('hevc')) 'h265',
      'h264',
    ].join(',');
  }

  /// The channel login pattern (the lower-cased room id).
  static final RegExp loginPattern = RegExp(r'^[a-z0-9_]{1,25}$');

  static const String _tagsHash = 'b4cb189d8d17aadf29c61e9d7c7e7dcfc932e93b77b3209af5661bffb484195f';
  static const String _directoriesHash = '2f67f71ba89f3c0ed26a141ec00da1defecb2303595f5cda4298169549783d9e';
  static const String _gameHash = '76cb069d835b8a02914c08dc42c421d0dafda8af5b113a3f19141824b901402f';
  static const String _searchHash = '7f3580f6ac6cd8aa1424cff7c974a07143827d6fa36bba1b54318fe7f0b68dc5';
  static const String _accessTokenHash = 'ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9';

  /// One channel with its stream: replaces 3.x's `ChannelShell` +
  /// `StreamMetadata` pair, whose `viewersCount` stopped being filled. The
  /// stream's `restriction` (null when anyone may watch) says whether it is
  /// for subscribers only.
  static const String userQuery =
      r'query($login: String!) { user(login: $login) { id login displayName description '
      'profileImageURL(width: 300) stream { id title type viewersCount createdAt '
      'previewImageURL(width: 640, height: 360) restriction { type } game { id name displayName slug } } '
      'lastBroadcast { title game { name displayName } } } }';

  /// The busiest live streams of the whole site, in the broadcast
  /// `languages` when given (the recommendations, 8-3). The web client has
  /// no persisted query for it; `first` is at most 30 and pages after the
  /// first need a browser's integrity token. `$languages` is the
  /// `Language` enum: since 2026-10 the schema rejects the query when it is
  /// declared `[String!]`, sent or not (E03.17).
  static const String streamsQuery =
      r'query($first: Int!, $after: Cursor, $languages: [Language!]) { streams(first: $first, after: $after, '
      r'options: {broadcasterLanguages: $languages}) { edges { cursor node { id title type viewersCount '
      'createdAt previewImageURL(width: 440, height: 248) restriction { type } broadcaster { id login '
      'displayName profileImageURL(width: 70) } game { id name displayName slug } } } '
      'pageInfo { hasNextPage } } }';

  /// The two `play_session_id`s 3.x picked from.
  static const List<String> playSessionIds = ['bdd22331a986c7f1073628f2fc5b19da', '064bc3ff1722b6f53b0b5b8c01e46ca5'];

  // Requests ------------------------------------------------------------------

  /// A persisted-query operation.
  static Map<String, Object?> persisted(String operation, String hash, Map<String, Object?> variables) => {
    'operationName': operation,
    'extensions': {
      'persistedQuery': {'version': 1, 'sha256Hash': hash},
    },
    'variables': variables,
  };

  /// `SearchCategoryTags`: every category tag.
  static Map<String, Object?> tagsOperation() =>
      persisted('SearchCategoryTags', _tagsHash, {'userQuery': '', 'limit': 100});

  /// `BrowsePage_AllDirectories` of one tag, by viewers, after [cursor].
  static Map<String, Object?> directoriesOperation(String tagId, {String? cursor}) =>
      persisted('BrowsePage_AllDirectories', _directoriesHash, {
        'limit': tagDirectoryLimit,
        'options': {
          'recommendationsContext': {'platform': 'web'},
          'requestID': 'JIRA-VXP-2397',
          'sort': 'VIEWER_COUNT',
          'tags': [tagId],
        },
        'cursor': ?cursor,
      });

  /// `DirectoryPage_Game` of the directory [slug]: [limit] streams by
  /// viewers after [cursor], in [languages] (all when empty; 3.x always
  /// asked for [legacyLanguages]).
  static Map<String, Object?> gameOperation(
    String slug, {
    required int limit,
    String? cursor,
    List<String> languages = const [],
  }) => persisted('DirectoryPage_Game', _gameHash, {
    'imageWidth': 50,
    'slug': slug,
    'options': {
      'sort': 'VIEWER_COUNT',
      'recommendationsContext': {'platform': 'web'},
      'requestID': 'JIRA-VXP-2397',
      'freeformTags': null,
      'tags': <String>[],
      'broadcasterLanguages': languages,
      'systemFilters': <String>[],
    },
    'sortTypeIsRecency': false,
    'limit': limit,
    'includeCostreaming': true,
    'cursor': ?cursor,
  });

  /// The raw [streamsQuery]: [limit] (1–30) of the site's busiest streams
  /// after [cursor], in [languages] (all when empty).
  static Map<String, Object?> streamsOperation({
    required int limit,
    String? cursor,
    List<String> languages = const [],
  }) => {
    'query': streamsQuery,
    'variables': {
      'first': limit.clamp(1, streamsLimit),
      'after': ?cursor,
      if (languages.isNotEmpty) 'languages': languages,
    },
  };

  /// The broadcast languages of a setting as Twitch spells them: upper
  /// case, `-` as `_`, each once; blanks and values that cannot be a
  /// language are left out (an unknown one fails the whole request).
  static List<String> normalizeLanguages(Iterable<String> languages) => [
    ...{
      for (final language in languages)
        if (language.trim().toUpperCase().replaceAll('-', '_') case final code when languagePattern.hasMatch(code))
          code,
    },
  ];

  /// `SearchResultsPage_SearchResults` for [keyword]; a later page names
  /// the channel index's [cursor] in `options.targets` (a top-level `cursor`
  /// is ignored by the server).
  static Map<String, Object?> searchOperation(String keyword, {String? cursor}) =>
      persisted('SearchResultsPage_SearchResults', _searchHash, {
        'platform': 'web',
        'query': keyword,
        'options': {
          'targets': cursor == null
              ? null
              : [
                  {'index': 'CHANNEL', 'cursor': cursor},
                ],
          'shouldSkipDiscoveryControl': false,
        },
        'requestID': '808c9f2e-f52e-431c-8dc7-d2e3c1831d77',
        'includeIsDJ': true,
      });

  /// The raw [userQuery] for [login].
  static Map<String, Object?> userOperation(String login) => {
    'query': userQuery,
    'variables': {'login': login},
  };

  /// `PlaybackAccessToken` of a live channel.
  static Map<String, Object?> accessTokenOperation(String login) => persisted('PlaybackAccessToken', _accessTokenHash, {
    'isLive': true,
    'login': login,
    'isVod': false,
    'vodID': '',
    'playerType': 'site',
    'isClip': false,
    'clipID': '',
    'platform': 'site',
  });

  /// The GraphQL request headers 3.x sent, with the adapter's [deviceId],
  /// asking for [language] ([acceptLanguage] unless told otherwise).
  /// [cookie] (the stored session) adds `Cookie` and, when it has an
  /// `auth-token`, `Authorization: OAuth`.
  static Map<String, String> gqlHeaders({
    required String deviceId,
    String cookie = '',
    String language = acceptLanguage,
  }) {
    final token = authToken(cookie);
    return {
      ..._identity(deviceId, language),
      'content-type': 'text/plain;charset=UTF-8',
      if (cookie.isNotEmpty) 'cookie': cookie,
      'authorization': ?(token == null ? null : 'OAuth $token'),
    };
  }

  /// The usher request headers: 3.x's GraphQL identity, without the session.
  static Map<String, String> usherHeaders({required String deviceId}) => _identity(deviceId, acceptLanguage);

  static Map<String, String> _identity(String deviceId, String language) => {
    'user-agent': userAgent,
    'accept-language': language,
    'accept': 'application/vnd.twitchtv.v5+json',
    'client-id': clientId,
    'origin': origin,
    'referer': '$origin/',
    'device-id': deviceId,
  };

  /// Media request headers for [roomId] (3.x's `PlaybackHeaderResolver`):
  /// UA, Origin and the channel page as Referer. The login cookie is not
  /// sent to the CDN (8-7; 3.x sent it).
  static Map<String, String> mediaHeaders(String roomId) {
    final id = roomId.trim();
    return {
      'user-agent': userAgent,
      'origin': origin,
      'referer': id.isEmpty ? '$origin/' : '$origin/${Uri.encodeComponent(id)}',
    };
  }

  /// A `Device-Id`: 32 lower-case hexadecimal digits.
  static String deviceId(Random random) => [for (var i = 0; i < 32; i++) '0123456789abcdef'[random.nextInt(16)]].join();

  /// The value of cookie [name] in [cookie] (names compared without case,
  /// `=` kept inside the value); null when missing or empty.
  static String? cookieValue(String cookie, String name) {
    for (final part in cookie.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0 || part.substring(0, separator).trim().toLowerCase() != name) continue;
      final value = part.substring(separator + 1).trim();
      return value.isEmpty ? null : value;
    }
    return null;
  }

  /// The OAuth token of a stored cookie (`auth-token`).
  static String? authToken(String cookie) => cookieValue(cookie, 'auth-token');

  /// The chat login of a stored cookie: `login` (lower case) with
  /// `auth-token`, or null unless both are there.
  static TwitchChatLogin? chatLogin(String cookie) {
    final token = authToken(cookie);
    final login = cookieValue(cookie, 'login')?.toLowerCase();
    return token == null || login == null ? null : (login: login, token: token);
  }

  /// The usher master playlist of [login] with 3.x's parameters (a random
  /// `p` and one of [playSessionIds]) and the codecs asked for (8-8):
  /// H.264 only when [preferH264], else HEVC and AV1 as well, as far as
  /// the engine decodes them ([codecs], see [supportedCodecs]).
  static Uri usherUrl(
    String login,
    TwitchAccessToken token,
    Random random, {
    bool preferH264 = true,
    Set<String>? codecs,
  }) {
    final session = playSessionIds[random.nextInt(playSessionIds.length)];
    return Uri.https('usher.ttvnw.net', '/api/channel/hls/$login.m3u8', {
      'acmb': 'e30=',
      'allow_source': 'true',
      'cdm': 'wv',
      'fast_bread': 'true',
      'p': '${random.nextInt(10000000)}',
      'platform': 'web',
      'play_session_id': session,
      'player_backend': 'mediaplayer',
      'player_version': '1.28.0-rc.1',
      'playlist_include_framerate': 'true',
      'reassignments_supported': 'true',
      'sig': token.signature,
      'supported_codecs': supportedCodecs(preferH264: preferH264, codecs: codecs),
      'token': token.value,
      'transcode_mode': 'cbr_v1',
    });
  }

  // GraphQL -------------------------------------------------------------------

  /// A GraphQL answer: an envelope, or a list of them for a batch. HTTP 401
  /// is `NeedsLogin` (a stale session), 429 `RateLimited`, 5xx
  /// `NetworkFailure`, another non-2xx status or a body that is no envelope
  /// `ApiChanged`; an integrity challenge anywhere is `RiskControl`.
  static Object decode(String body, {required int status, required String what}) {
    if (status == 401) throw NeedsLogin(_site, '$what: HTTP 401');
    if (status == 429) throw RateLimited(_site, detail: '$what: HTTP 429');
    if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, '$what: HTTP $status (${_snippet(body)})');
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic> && decoded is! List) {
      throw ApiChanged(_site, '$what: not a GraphQL answer (${_snippet(body)})');
    }
    if (isIntegrityRejection(decoded)) throw RiskControl(_site, detail: '$what: integrity check required');
    return decoded!;
  }

  /// Whether Twitch asked for a browser's integrity token: an error
  /// mentioning `failed integrity check` or `integrity token` (3.x's
  /// `hasIntegrityError`), or an `extensions.challenge`, in any envelope.
  static bool isIntegrityRejection(Object? decoded) {
    if (decoded is List) return decoded.any(isIntegrityRejection);
    if (decoded is! Map) return false;
    final extensions = decoded['extensions'];
    if (extensions is Map && extensions['challenge'] != null) return true;
    final errors = decoded['errors'];
    return errors is List &&
        errors.any((error) {
          final message = error is Map ? '${error['message'] ?? ''}'.toLowerCase() : '';
          return message.contains('failed integrity check') || message.contains('integrity token');
        });
  }

  /// The envelopes of a batch of [expected] operations, in request order.
  static List<Object?> batch(Object? decoded, {required int expected, required String what}) {
    final envelopes = decoded is List ? decoded : [decoded];
    if (envelopes.length != expected) {
      throw ApiChanged(_site, '$what: ${envelopes.length} answers for $expected operations');
    }
    return envelopes;
  }

  /// The `data` of one envelope ([decoded] may be a batch of one). Errors
  /// only count when they left no data (partial `service error`s are
  /// common): then the envelope is `ApiChanged`.
  static Map<String, dynamic> _data(Object? decoded, String what) {
    final envelope = _envelope(decoded, what);
    final data = envelope.data;
    if (data != null) return data;
    final messages = envelope.errors.isEmpty ? '' : ' (${envelope.errors.join('; ')})';
    throw ApiChanged(_site, '$what: no data$messages');
  }

  /// One envelope's `data` (null when missing) and error messages. An
  /// unknown persisted query is `ApiChanged` whatever else it holds: the web
  /// client's hash changed and every request with it fails.
  static ({Map<String, dynamic>? data, List<String> errors}) _envelope(Object? decoded, String what) {
    final envelope = decoded is List ? (decoded.isEmpty ? null : decoded.first) : decoded;
    if (envelope is! Map<String, dynamic>) throw ApiChanged(_site, '$what: no envelope');
    final errors = [
      for (final error in _list(envelope['errors']))
        if (error is Map) '${error['message'] ?? ''}',
    ];
    if (errors.any((message) => message.contains('PersistedQueryNotFound'))) {
      throw ApiChanged(_site, '$what: persisted query no longer known');
    }
    return (data: _object(envelope['data']), errors: errors);
  }

  // Catalog -------------------------------------------------------------------

  /// `SearchCategoryTags`: every tag in the server's order, named by
  /// `tagName` as in 3.x; `localizedName` only when `tagName` is empty, and
  /// a tag with neither keeps its empty name (see [namedTags]).
  static List<TwitchTag> tags(Object? decoded) {
    final list = _data(decoded, 'SearchCategoryTags')['searchCategoryTags'];
    if (list is! List) throw const ApiChanged(_site, 'SearchCategoryTags: no list');
    return [
      for (final tag in list)
        if (tag is Map)
          if (jsonString(tag['id']) case final id?)
            (id: id, name: jsonString(tag['tagName']) ?? jsonString(tag['localizedName']) ?? ''),
    ];
  }

  /// [tags] with each empty name taken from [fallback] (the same tags asked
  /// for in English): Twitch has no Chinese name for some tags (S01-tags:
  /// "Gambling"). A tag [fallback] cannot name keeps its empty name.
  static List<TwitchTag> namedTags(List<TwitchTag> tags, List<TwitchTag> fallback) {
    final names = {for (final tag in fallback) tag.id: tag.name};
    return [
      for (final tag in tags)
        if (tag.name.isNotEmpty) tag else (id: tag.id, name: names[tag.id] ?? ''),
    ];
  }

  /// One `BrowsePage_AllDirectories` envelope: the directories of [tag] as
  /// 3.x's areas (`areaId` the game id, `shortName` the slug that
  /// `DirectoryPage_Game` needs, the box art), and the cursor of the next
  /// page when `pageInfo` says there is one. An envelope with errors and no
  /// data is a page without areas, as 3.x read it.
  static ({List<LiveArea> areas, String? cursor}) directories(Object? envelope, TwitchTag tag) {
    final data = _envelope(envelope, 'BrowsePage_AllDirectories').data;
    final connection = _connection(data?['directoriesWithTags']);
    final areas = [
      for (final edge in connection.edges)
        if (_object(edge['node']) case final node?)
          if ((jsonString(node['id']), jsonString(node['slug'])) case (final String id, final String slug))
            LiveArea(
              platform: _site,
              areaType: tag.id,
              typeName: tag.name,
              areaId: id,
              areaName: _gameName(node),
              areaPic: _image(node['avatarURL']),
              shortName: slug,
            ),
    ];
    return (areas: areas, cursor: _nextCursor(connection));
  }

  // Lists ---------------------------------------------------------------------

  /// `DirectoryPage_Game`: the streams of a directory as 3.x's cards, and
  /// the cursor of the next page when `pageInfo` says there is one. A
  /// stream is live, or a replay when it is a rerun (8-9; 3.x called every
  /// card live). The answer has no start time or restriction. An unknown
  /// directory (`game == null`) is `NotFound` (8-6; 3.x showed no streams).
  static ({List<LiveRoom> rooms, String? cursor}) gameStreams(
    Object? decoded, {
    required DateTime now,
    TwitchChatLogin? chat,
    String slug = '',
  }) {
    final game = _object(_data(decoded, 'DirectoryPage_Game')['game']);
    if (game == null) throw NotFound(_site, 'DirectoryPage_Game: no directory $slug'.trim());
    final connection = _connection(game['streams']);
    final rooms = [for (final edge in connection.edges) ?_streamCard(_object(edge['node']), now: now, chat: chat)];
    return (rooms: rooms, cursor: _nextCursor(connection));
  }

  /// The raw [streamsQuery]: the site's busiest streams as cards (the
  /// recommendations, 8-3), each with its start time and restriction, and
  /// the cursor of the next page when `pageInfo` says there is one.
  static ({List<LiveRoom> rooms, String? cursor}) streams(
    Object? decoded, {
    required DateTime now,
    TwitchChatLogin? chat,
  }) {
    final connection = _connection(_data(decoded, 'streams')['streams']);
    final rooms = [for (final edge in connection.edges) ?_streamCard(_object(edge['node']), now: now, chat: chat)];
    return (rooms: rooms, cursor: _nextCursor(connection));
  }

  /// One stream node of a list as a card: the broadcaster's login as room,
  /// its display name (the login without one), live or a rerun's replay,
  /// the preview as cover, the game's Chinese name as area. The start time
  /// (`createdAt`) and restriction come with the raw [streamsQuery] only.
  /// Null without a broadcaster login.
  static LiveRoom? _streamCard(Map<String, dynamic>? node, {required DateTime now, TwitchChatLogin? chat}) {
    final broadcaster = _object(node?['broadcaster']);
    final login = jsonString(broadcaster?['login']);
    if (node == null || broadcaster == null || login == null) return null;
    final area = _object(node['game']);
    final viewers = _text(node['viewersCount'] ?? 0);
    return LiveRoom(
      roomId: login,
      platform: _site,
      title: _text(node['title']),
      nick: broadcaster['displayName'] == null ? login : _text(broadcaster['displayName']),
      avatar: _image(broadcaster['profileImageURL']),
      cover: _cover(node['previewImageURL'], now),
      area: area == null ? '' : _gameName(area),
      watching: viewers,
      onlineViewers: viewers,
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: _isRerun(node) ? LiveStatus.replay : LiveStatus.live,
      startedAt: _time(node['createdAt']),
      restriction: restriction(node),
      introduction: '',
      notice: '',
      danmakuData: TwitchDanmakuArgs(channel: login.toLowerCase(), chat: chat),
    );
  }

  /// `SearchResultsPage_SearchResults`: channels, live or not, as 3.x's
  /// cards, and the channel index's cursor (none when empty or when the page
  /// had no channels). A rerun is a replay (8-9); a stream's start time is
  /// its broadcast's `startedAt` (`lastBroadcast` is the stream on air when
  /// their ids match). No restriction is given.
  static ({List<LiveRoom> rooms, String? cursor}) searchPage(
    Object? decoded, {
    required DateTime now,
    TwitchChatLogin? chat,
  }) {
    final search = _object(_data(decoded, 'SearchResultsPage_SearchResults')['searchFor']);
    final channels = _object(search?['channels']);
    if (channels == null) return (rooms: const [], cursor: null);
    final rooms = <LiveRoom>[];
    for (final edge in _list(channels['edges'])) {
      final item = _object(_object(edge)?['item']);
      final login = jsonString(item?['login']);
      if (item == null || login == null) continue;
      final stream = _object(item['stream']);
      final broadcast = _object(item['lastBroadcast']);
      final current =
          stream != null &&
          jsonString(stream['id']) != null &&
          jsonString(stream['id']) == jsonString(broadcast?['id']);
      final viewers = _text(stream?['viewersCount'] ?? 0);
      rooms.add(
        LiveRoom(
          roomId: login,
          platform: _site,
          title: _text(_object(item['broadcastSettings'])?['title']),
          nick: _text(item['displayName']),
          avatar: _image(item['profileImageURL']),
          cover: _cover(stream?['previewImageURL'], now),
          area: _text(_object(stream?['game'])?['displayName']),
          watching: viewers,
          onlineViewers: viewers,
          audienceMetricType: AudienceMetricType.onlineViewers,
          liveStatus: stream == null
              ? LiveStatus.offline
              : _isRerun(stream)
              ? LiveStatus.replay
              : LiveStatus.live,
          startedAt: current ? _time(broadcast?['startedAt']) : null,
          introduction: '',
          notice: '',
          danmakuData: TwitchDanmakuArgs(channel: login.toLowerCase(), chat: chat),
        ),
      );
    }
    final cursor = jsonString(channels['cursor']);
    return (rooms: rooms, cursor: rooms.isEmpty ? null : cursor);
  }

  // Rooms ---------------------------------------------------------------------

  /// The raw `user` query: the room as the user asked for it
  /// ([requestedId]), with 3.x's fields where no upgrade changed them: the
  /// last broadcast's title, the profile image as avatar, no notice, viewers
  /// `'0'` when nothing is on air. A stream of type `live` is live, a rerun
  /// a replay (8-9; 3.x: offline), any other type or none offline. While a
  /// stream is on (live or rerun) the room has:
  /// - the stream's preview as cover (8-5; else the profile image, as 3.x),
  ///   with 3.x's list `?&t=<Unix seconds of [now]>`;
  /// - the game's Chinese name as area (8-2; 3.x: its English `name`);
  /// - its start time (`createdAt`) and restriction.
  ///
  /// The channel's description is the introduction (8-4). `user == null` is
  /// `NotFound`; another login in the answer is `ApiChanged`.
  static LiveRoom roomDetail(
    Object? decoded, {
    required String requestedId,
    required DateTime now,
    TwitchChatLogin? chat,
  }) {
    final id = requestedId.trim();
    final login = id.toLowerCase();
    final user = _object(_data(decoded, 'user')['user']);
    if (user == null) throw NotFound(_site, 'user: no channel $login');
    final answered = jsonString(user['login'])?.toLowerCase();
    if (answered != login) throw ApiChanged(_site, 'user: answered $answered for $login');
    final stream = _object(user['stream']);
    final status = switch (stream?['type']) {
      'live' => LiveStatus.live,
      'rerun' => LiveStatus.replay,
      _ => LiveStatus.offline,
    };
    final onAir = status != LiveStatus.offline;
    final viewers = onAir ? _text(stream!['viewersCount'] ?? 0) : '0';
    final game = _object(stream?['game']);
    final profile = _text(user['profileImageURL']);
    final preview = onAir ? _cover(stream!['previewImageURL'], now) : '';
    return LiveRoom(
      roomId: id,
      platform: _site,
      userId: id,
      link: '$origin/$id',
      title: _text(_object(user['lastBroadcast'])?['title']),
      nick: _text(user['displayName']),
      avatar: profile,
      cover: preview.isEmpty ? profile : preview,
      area: game == null ? null : _gameName(game),
      watching: viewers,
      onlineViewers: viewers,
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: status,
      startedAt: onAir ? _time(stream!['createdAt']) : null,
      restriction: onAir ? restriction(stream) : null,
      introduction: _text(user['description']).trim(),
      notice: '',
      danmakuData: TwitchDanmakuArgs(channel: login, chat: chat),
    );
  }

  /// The restriction of a stream node that was asked for its `restriction`
  /// ([userQuery], [streamsQuery]): none when it is null; subscribers only
  /// for Twitch's subscriber-only streams (a type naming `SUB`, such as
  /// `SUB_ONLY_LIVE`); another kind is `unplayable`, since what it asks of
  /// the viewer is unknown. Null when the node has no such key (the
  /// persisted list queries do not ask for it).
  static LiveRestriction? restriction(Map<String, dynamic>? stream) {
    if (stream == null || !stream.containsKey('restriction')) return null;
    final value = stream['restriction'];
    if (value == null) return LiveRestriction.none;
    final type = '${_object(value)?['type'] ?? ''}'.toUpperCase();
    return type.contains('SUB') ? LiveRestriction.subscribersOnly : LiveRestriction.unplayable;
  }

  // Streams -------------------------------------------------------------------

  /// `PlaybackAccessToken` of [login]: a null token is an unknown channel;
  /// the token's own `authorization` says whether this viewer may watch
  /// (`geo` reasons are `RegionBlocked`, others `NeedsLogin`).
  static TwitchAccessToken accessToken(Object? decoded, {required String login}) {
    final token = _object(_data(decoded, 'PlaybackAccessToken')['streamPlaybackAccessToken']);
    if (token == null) throw NotFound(_site, 'PlaybackAccessToken: no channel $login');
    final value = jsonString(token['value']);
    final signature = jsonString(token['signature']);
    if (value == null || signature == null) throw const ApiChanged(_site, 'PlaybackAccessToken: incomplete');
    Object? claims;
    try {
      claims = jsonDecode(value);
    } on FormatException {
      claims = null;
    }
    final authorization = _object(_object(claims)?['authorization']);
    if (authorization?['forbidden'] == true) {
      final reason = jsonString(authorization?['reason']) ?? '';
      if (reason.toLowerCase().contains('geo')) throw RegionBlocked(_site, 'PlaybackAccessToken: $reason');
      throw NeedsLogin(_site, 'PlaybackAccessToken: $reason');
    }
    return (value: value, signature: signature);
  }

  /// The usher answer: 404 is a channel that is not broadcasting; 403 names
  /// why this viewer may not watch (`geo` is `RegionBlocked`, others
  /// `NeedsLogin`).
  static void usherStatus(int status, String body) {
    if (status >= 200 && status < 300) return;
    if (status >= 500) throw NetworkFailure(_site, 'usher: HTTP $status');
    if (status == 429) throw const RateLimited(_site, detail: 'usher: HTTP 429');
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    final first = _object(decoded is List && decoded.isNotEmpty ? decoded.first : decoded);
    final code = jsonString(first?['error_code']) ?? '';
    final message = jsonString(first?['error']) ?? '';
    final detail = 'usher: HTTP $status $code $message'.trim();
    if (status == 404) throw StreamUnavailable(_site, detail);
    if (status == 403) {
      if ('$code $message'.toLowerCase().contains('geo')) throw RegionBlocked(_site, detail);
      throw NeedsLogin(_site, detail);
    }
    throw ApiChanged(_site, detail);
  }

  static final RegExp _attribute = RegExp('([A-Z0-9-]+)=("[^"]*"|[^,]*)');

  /// The master playlist (3.x's `parseMasterPlaylist`): each
  /// `#EXT-X-STREAM-INF` with the URI after it, grouped by height, frame
  /// rate, bandwidth and `VIDEO` group; the broadcaster's own stream
  /// (`chunked`) first, the rest by bandwidth. `data` is the list of the
  /// variant URLs ([TwitchVariants], with the codec `CODECS` names). No
  /// variant is `StreamUnavailable`.
  static List<LivePlayQuality> qualities(String playlist, {required Uri master}) {
    if (!playlist.trimLeft().startsWith('#EXTM3U')) {
      throw ApiChanged(_site, 'usher: not a playlist (${_snippet(playlist)})');
    }
    final grouped = <String, ({String label, int sort, List<String> urls, String? codec})>{};
    Map<String, String>? pending;
    for (final raw in playlist.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        pending = _attributes(line.substring('#EXT-X-STREAM-INF:'.length));
        continue;
      }
      if (line.isEmpty || line.startsWith('#') || pending == null) continue;
      final attributes = pending;
      pending = null;
      final Uri uri;
      try {
        uri = master.resolve(line);
      } on FormatException {
        continue;
      }
      if (!uri.isScheme('http') && !uri.isScheme('https')) continue;
      final bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0;
      final resolution = RegExp(r'^(\d+)x(\d+)$').firstMatch(attributes['RESOLUTION'] ?? '');
      final height = int.tryParse(resolution?.group(2) ?? '') ?? 0;
      final frameRate = double.tryParse(attributes['FRAME-RATE'] ?? '') ?? 0;
      final group = (attributes['VIDEO'] ?? '').toLowerCase();
      final source = group == 'chunked';
      final id = '$height:${frameRate.round()}:$bandwidth:$group';
      final url = uri.toString();
      final existing = grouped[id];
      if (existing == null) {
        grouped[id] = (
          label: _qualityName(bandwidth, height: height, frameRate: frameRate, source: source),
          sort: source ? 1 << 30 : bandwidth,
          urls: [url],
          codec: videoCodec(attributes['CODECS'] ?? ''),
        );
      } else if (!existing.urls.contains(url)) {
        existing.urls.add(url);
      }
    }
    if (grouped.isEmpty) throw const StreamUnavailable(_site, 'usher: no variant');
    return [
      for (final MapEntry(:key, :value) in grouped.entries)
        LivePlayQuality(
          quality: value.label,
          id: key,
          sort: value.sort,
          data: TwitchVariants(value.urls, codec: value.codec),
        ),
    ]..sort((a, b) => b.sort.compareTo(a.sort));
  }

  /// The video codec of an HLS `CODECS` list: `avc` (`avc1`, `avc3`),
  /// `hevc` (`hvc1`, `hev1`) or `av1` (`av01`); null for none of them.
  static String? videoCodec(String codecs) {
    for (final entry in codecs.toLowerCase().split(',')) {
      final name = entry.trim().split('.').first;
      switch (name) {
        case 'avc1' || 'avc3':
          return 'avc';
        case 'hvc1' || 'hev1':
          return 'hevc';
        case 'av01':
          return 'av1';
      }
    }
    return null;
  }

  /// The quality of [fresh] that is [wanted]: the same id, else the same
  /// `VIDEO` group (the id's bandwidth moves between playlists), else the
  /// same label; null when none is.
  static LivePlayQuality? sameQuality(List<LivePlayQuality> fresh, LivePlayQuality wanted) {
    final id = '${wanted.selectionId}';
    String group(Object? value) => '$value'.split(':').last;
    return fresh.where((quality) => '${quality.selectionId}' == id).firstOrNull ??
        (id.contains(':') ? fresh.where((quality) => group(quality.id) == group(id)).firstOrNull : null) ??
        fresh.where((quality) => quality.quality == wanted.quality).firstOrNull;
  }

  /// The lines of one quality: each variant URL (HLS, lined by its host,
  /// encoded with [codec]) with the media headers for [roomId]. Variant
  /// playlists outlive the 20-minute access token, so no lease.
  static LivePlayUrlResolution resolution(
    Iterable<String> urls, {
    required String roomId,
    required Object? appliedQualityData,
    String? codec,
  }) {
    final headers = mediaHeaders(roomId);
    return LivePlayUrlResolution.lines([
      for (final url in urls)
        if (url.trim().isNotEmpty)
          LivePlayLine(
            url.trim(),
            headers: headers,
            format: StreamFormat.hls,
            codec: codec,
            lineId: Uri.tryParse(url.trim())?.host,
          ),
    ], appliedQualityData: appliedQualityData);
  }

  // Helpers -------------------------------------------------------------------

  static Map<String, String> _attributes(String text) => {
    for (final match in _attribute.allMatches(text))
      match.group(1)!: switch (match.group(2) ?? '') {
        final raw when raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"') => raw.substring(1, raw.length - 1),
        final raw => raw,
      },
  };

  /// 3.x's `_qualityName`: `<height>p[<fps>][ (Source)]` through
  /// [LiveQualityLabel] (the frame rate from 45 fps up), or a label from
  /// the bandwidth when there is no resolution.
  static String _qualityName(int bandwidth, {required int height, required double frameRate, required bool source}) {
    if (height > 0) {
      final fps = frameRate >= 45 ? '${frameRate.round()}' : '';
      return LiveQualityLabel.normalize(
        platform: _site,
        rawLabel: '${height}p$fps${source ? ' (Source)' : ''}',
        bitrate: bandwidth,
        resolution: '${height * 16 ~/ 9}x$height',
      );
    }
    if (source) return '原画';
    if (bandwidth > 5000000) return '1080P';
    if (bandwidth > 2500000) return '720P';
    if (bandwidth > 1000000) return '480P';
    if (bandwidth > 500000) return '360P';
    return '自动';
  }

  /// The last edge's cursor when `pageInfo.hasNextPage` is true, else null.
  static String? _nextCursor(({List<Map<String, dynamic>> edges, bool hasNextPage}) connection) =>
      connection.hasNextPage && connection.edges.isNotEmpty ? jsonString(connection.edges.last['cursor']) : null;

  /// A connection's edges and whether `pageInfo.hasNextPage` is true
  /// (3.x's `parseConnection`: a missing `pageInfo` ends the list).
  static ({List<Map<String, dynamic>> edges, bool hasNextPage}) _connection(Object? value) {
    final connection = _object(value);
    return (
      edges: [for (final edge in _list(connection?['edges'])) ?_object(edge)],
      hasNextPage: _object(connection?['pageInfo'])?['hasNextPage'] == true,
    );
  }

  /// An image URL as Twitch gives it: straight from its CDN (8-7; 3.x
  /// rewrote every list image through the `i2.wp.com` proxy).
  static String _image(Object? value) => _text(value);

  /// A stream preview with 3.x's `?&t=<Unix seconds>`, so a refresh fetches
  /// the current frame; empty without a preview.
  static String _cover(Object? value, DateTime now) {
    final url = _image(value);
    return url.trim().isEmpty ? '' : '$url?&t=${now.millisecondsSinceEpoch ~/ 1000}';
  }

  /// A game's (directory's) name in the requested language, `displayName`
  /// (Chinese under [acceptLanguage]); its `name` when there is none.
  static String _gameName(Map<String, dynamic> game) {
    final display = _text(game['displayName']);
    return display.isNotEmpty ? display : _text(game['name']);
  }

  /// Whether a stream is a rerun (Twitch's replay of a past broadcast).
  static bool _isRerun(Map<String, dynamic> stream) => stream['type'] == 'rerun';

  /// An ISO 8601 time (`2026-09-27T12:49:35Z`) as UTC; null when missing,
  /// unreadable or not after 1970.
  static DateTime? _time(Object? value) {
    final time = DateTime.tryParse(jsonString(value) ?? '')?.toUtc();
    return time == null || time.millisecondsSinceEpoch <= 0 ? null : time;
  }
}

/// A JSON value as text, as 3.x's `toString()` wrote it; '' for null.
String _text(Object? value) => value == null ? '' : '$value';

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}
