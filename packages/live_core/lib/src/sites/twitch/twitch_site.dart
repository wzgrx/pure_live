import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/twitch/twitch_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'twitch';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// The web client's id (spec/sites/twitch.md §6.1).
const twitchClientId = 'kimne78kx3ncx6brgo4mv6wki5h1ko';

/// §2.1 the category of the busiest directories, ahead of the genre tags.
const _topCategory = 'top';

/// Persisted-query hashes of the web client (spec §2–§6).
abstract final class _Hash {
  static const tags = 'b4cb189d8d17aadf29c61e9d7c7e7dcfc932e93b77b3209af5661bffb484195f';
  static const directories = '2f67f71ba89f3c0ed26a141ec00da1defecb2303595f5cda4298169549783d9e';
  static const game = '76cb069d835b8a02914c08dc42c421d0dafda8af5b113a3f19141824b901402f';
  static const search = '7f3580f6ac6cd8aa1424cff7c974a07143827d6fa36bba1b54318fe7f0b68dc5';
  static const accessToken = 'ed230aa1e33e07eebb8928504583da78a5173989fadfb1ac94be06a04f3cdbe9';
}

/// §2.3 the busiest live streams (a raw query: the web client has no
/// persisted query for the whole site).
const _streamsQuery =
    r'query($first: Int!) { streams(first: $first) { edges { node { id title type viewersCount createdAt '
    'previewImageURL(width: 440, height: 248) broadcaster { id login displayName profileImageURL(width: 70) } '
    'game { id name displayName slug } } } } }';

/// §4 one channel with its stream (raw query; replaces 3.x's ChannelShell and
/// StreamMetadata pair).
const _userQuery =
    r'query($login: String!) { user(login: $login) { id login displayName description '
    'profileImageURL(width: 300) stream { id title type viewersCount createdAt '
    'previewImageURL(width: 640, height: 360) game { id name displayName slug } } '
    'lastBroadcast { title game { name displayName } } } }';

/// §1 hosts of channel pages.
const _hosts = {'twitch.tv', 'www.twitch.tv', 'm.twitch.tv', 'go.twitch.tv'};

/// §1 first path segments that are not channels.
const _reserved = {
  'directory',
  'downloads',
  'drops',
  'friends',
  'following',
  'inventory',
  'jobs',
  'login',
  'messages',
  'moderator',
  'p',
  'payments',
  'prime',
  'search',
  'settings',
  'signup',
  'store',
  'subscriptions',
  'turbo',
  'videos',
  'wallet',
};

/// The Twitch adapter (spec/sites/twitch.md): GraphQL over [LiveHttp] and
/// the usher master playlist. Everything works anonymously through plain
/// HTTP except the pages after the first of a list, which need a browser's
/// integrity token (spec §8); lists therefore stop after their first page.
/// The user's `auth-token` cookie, when stored, goes with the playback token
/// request only.
final class TwitchSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter; [random] (device id, usher nonce) is injectable
  /// for tests.
  new(this.http, {this._cookies, Random? random})
    : _random = random ?? Random.secure(),
      _deviceId = _hex(random ?? Random.secure(), 32);

  /// Transport.
  final LiveHttp http;
  final CookieVault? _cookies;
  final Random _random;

  /// §6.1 `Device-Id`, one per adapter.
  final String _deviceId;

  @override
  String get id => _site;

  @override
  String get name => 'Twitch';

  static String _hex(Random random, int length) =>
      List.generate(length, (_) => '0123456789abcdef'[random.nextInt(16)]).join();

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  /// §6.1 the user's OAuth token from the `auth-token` cookie.
  String? _authToken() {
    final cookie = _cookies?.cookieFor(_site);
    if (cookie == null) return null;
    for (final part in cookie.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0 || part.substring(0, separator).trim().toLowerCase() != 'auth-token') continue;
      final value = part.substring(separator + 1).trim();
      return value.isEmpty ? null : value;
    }
    return null;
  }

  static Map<String, Object?> _persisted(String operation, String hash, Map<String, Object?> variables) => {
    'operationName': operation,
    'variables': variables,
    'extensions': {
      'persistedQuery': {'version': 1, 'sha256Hash': hash},
    },
  };

  /// One GraphQL request ([body] is an operation or a batch of them).
  Future<String> _gql(Object body, {String? auth}) async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https('gql.twitch.tv', '/gql'),
        method: 'POST',
        headers: {
          'user-agent': _userAgent,
          'client-id': twitchClientId,
          'device-id': _deviceId,
          'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
          'origin': 'https://www.twitch.tv',
          'referer': 'https://www.twitch.tv/',
          'content-type': 'text/plain;charset=UTF-8',
          if (auth != null) 'authorization': 'OAuth $auth',
        },
        body: utf8.encode(jsonEncode(body)),
      ),
    );
    final status = response.status;
    if (status >= 500) throw NetworkFailure(_site, 'gql HTTP $status');
    if (status == 429) throw const RateLimited(_site, detail: 'gql HTTP 429');
    if (status == 401) throw const NeedsLogin(_site, 'gql HTTP 401');
    if (status != 200) throw ApiChanged(_site, 'gql HTTP $status');
    return response.text;
  }

  Map<String, Object?> _directories(String? tag, int limit) =>
      _persisted('BrowsePage_AllDirectories', _Hash.directories, {
        'limit': limit,
        'options': {
          'recommendationsContext': {'platform': 'web'},
          'requestID': 'JIRA-VXP-2397',
          'sort': 'VIEWER_COUNT',
          'tags': [?tag],
        },
      });

  @override
  Future<List<Category>> categories() async {
    final tags = TwitchParse.tags(
      await _gql(_persisted('SearchCategoryTags', _Hash.tags, {'userQuery': '', 'limit': 100})),
    );
    final wanted = <(Category, Map<String, Object?>)>[
      (const Category(id: _topCategory, name: '热门'), _directories(null, twitchTopDirectoryLimit)),
      for (final tag in tags) (Category(id: tag.id, name: tag.name), _directories(tag.id, twitchTagDirectoryLimit)),
    ];
    final categories = <Category>[];
    for (var start = 0; start < wanted.length; start += twitchBatchLimit) {
      final chunk = wanted.sublist(start, min(start + twitchBatchLimit, wanted.length));
      final envelopes = TwitchParse.batch(
        await _gql([for (final (_, operation) in chunk) operation]),
        expected: chunk.length,
      );
      for (final (index, (category, _)) in chunk.indexed) {
        final areas = TwitchParse.directories(envelopes[index], categoryId: category.id);
        if (areas.isNotEmpty) categories.add(Category(id: category.id, name: category.name, areas: areas));
      }
    }
    return categories;
  }

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    // §2.4 later pages need an integrity token; the first page is the list.
    if (cursor != null) return const Page.empty();
    final text = await _gql([
      _persisted('DirectoryPage_Game', _Hash.game, {
        'imageWidth': 50,
        'slug': area.id,
        'options': {
          'sort': 'VIEWER_COUNT',
          'recommendationsContext': {'platform': 'web'},
          'requestID': 'JIRA-VXP-2397',
          'freeformTags': null,
          'tags': <String>[],
          'broadcasterLanguages': <String>[],
          'systemFilters': <String>[],
        },
        'sortTypeIsRecency': false,
        'limit': twitchStreamLimit,
        'includeCostreaming': true,
      }),
    ]);
    return TwitchParse.gameStreams(text, slug: area.id);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    if (cursor != null) return const Page.empty();
    return TwitchParse.streams(
      await _gql({
        'query': _streamsQuery,
        'variables': {'first': twitchRecommendedLimit},
      }),
    );
  }

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const Page.empty();
    return TwitchParse.searchPage(
      await _gql(
        _persisted('SearchResultsPage_SearchResults', _Hash.search, {
          'platform': 'web',
          'query': text,
          'options': {
            'targets': cursor == null
                ? null
                : [
                    {'index': 'CHANNEL', 'cursor': cursor.value},
                  ],
            'shouldSkipDiscoveryControl': false,
          },
          'requestID': '808c9f2e-f52e-431c-8dc7-d2e3c1831d77',
          'includeIsDJ': true,
        }),
      ),
    );
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final login = ref.roomId.toLowerCase();
    if (!TwitchParse.isLogin(login)) throw NotFound(_site, 'not a channel login: ${ref.roomId}');
    return TwitchParse.detail(
      await _gql({
        'query': _userQuery,
        'variables': {'login': login},
      }),
      login: login,
    );
  }

  /// §6.1 the playback token; with the user's token first, anonymous when
  /// the user's token is refused.
  Future<TwitchAccessToken> _accessToken(String login) async {
    final operation = _persisted('PlaybackAccessToken', _Hash.accessToken, {
      'isLive': true,
      'login': login,
      'isVod': false,
      'vodID': '',
      'playerType': 'site',
      'isClip': false,
      'clipID': '',
      'platform': 'site',
    });
    final auth = _authToken();
    if (auth != null) {
      try {
        return TwitchParse.accessToken(await _gql(operation, auth: auth), login: login);
      } on NeedsLogin {
        // A stale token must not block anonymous playback (3.x REG).
      }
    }
    return TwitchParse.accessToken(await _gql(operation), login: login);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final login = room.ref.roomId.toLowerCase();
    final token = await _accessToken(login);
    final url = TwitchParse.usherUrl(login, token, nonce: _random.nextInt(10000000));
    final response = await _send(
      LiveRequest(
        site: _site,
        url: url,
        headers: const {
          'user-agent': _userAgent,
          'origin': 'https://www.twitch.tv',
          'referer': 'https://www.twitch.tv/',
        },
      ),
    );
    TwitchParse.usherStatus(response.status, response.text);
    final variants = TwitchParse.master(response.text, base: url);
    final qualities = [for (final variant in variants) variant.quality];
    final chosen = variants.where((v) => v.quality.id == quality?.id).firstOrNull ?? variants.first;
    return StreamSet(
      qualities: qualities,
      selected: chosen.quality,
      lines: [
        StreamLine(
          url: chosen.url,
          format: StreamFormat.hls,
          lineId: chosen.url.host,
          requested: chosen.quality,
          confirmed: chosen.quality,
          headers: const {'user-agent': _userAgent},
          codec: chosen.codec,
        ),
      ],
    );
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (TwitchParse.isLogin(text.toLowerCase()) && !text.contains('.')) return RoomRef(_site, text.toLowerCase());
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? (text.contains('twitch.tv') ? 'https://$text' : text));
    if (url == null) return null;
    final host = url.host.toLowerCase();
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    String? login;
    if (host == 'player.twitch.tv') {
      login = url.queryParameters['channel'];
    } else if (_hosts.contains(host) && segments.isNotEmpty) {
      login = segments.first == 'popout' ? segments.elementAtOrNull(1) : segments.first;
      if (_reserved.contains(login?.toLowerCase())) login = null;
    }
    final normalized = login?.toLowerCase();
    return normalized != null && TwitchParse.isLogin(normalized) ? RoomRef(_site, normalized) : null;
  }
}
