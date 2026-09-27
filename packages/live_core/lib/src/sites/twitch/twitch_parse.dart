import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'twitch';

/// Rooms of a stream list: the first page is all an anonymous client gets
/// (spec/sites/twitch.md §2.4), so it asks for the most the API gives.
const twitchStreamLimit = 100;

/// Streams of the site-wide list: the raw `streams` field allows at most 30
/// (spec §2.3).
const twitchRecommendedLimit = 30;

/// Directories per category tag (spec §2.1).
const twitchTagDirectoryLimit = 30;

/// Directories of the "top" category (spec §2.1).
const twitchTopDirectoryLimit = 100;

/// Operations one GraphQL request may carry (`BATCH_LIMIT_EXCEEDED` above).
const twitchBatchLimit = 35;

/// A category tag of `SearchCategoryTags` (spec §2.1).
typedef TwitchTag = ({String id, String name});

/// `PlaybackAccessToken`: the token and its signature (spec §6.1).
typedef TwitchAccessToken = ({String value, String signature});

/// One variant of the usher master playlist (spec §5).
typedef TwitchVariant = ({Quality quality, Uri url, String? codec});

/// Pure parsing of Twitch responses (spec/sites/twitch.md). Every function
/// takes the raw response text and returns domain values or throws a
/// `SiteError`.
abstract final class TwitchParse {
  static Object? _json(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  static Map<String, dynamic> _map(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    throw ApiChanged(_site, '$what: expected an object');
  }

  /// A channel login: 1–25 letters, digits or underscores, lower case.
  static bool isLogin(String value) => RegExp(r'^[a-z0-9_]{1,25}$').hasMatch(value);

  /// §8 the GraphQL errors of one envelope: an integrity challenge is
  /// RiskControl, an unknown persisted query ApiChanged; other errors only
  /// matter when they left no data (partial `service error`s are common).
  static void _errors(Map<String, dynamic> envelope, String what, {Object? data}) {
    final errors = envelope['errors'];
    if (errors is! List || errors.isEmpty) return;
    final messages = [
      for (final error in errors)
        if (error is Map) '${error['message'] ?? ''}',
    ];
    final challenge = envelope['extensions'] is Map ? (envelope['extensions'] as Map)['challenge'] : null;
    if (challenge != null || messages.any((m) => m.contains('integrity'))) {
      throw RiskControl(_site, detail: '$what: integrity check required');
    }
    if (messages.any((m) => m.contains('PersistedQueryNotFound'))) {
      throw ApiChanged(_site, '$what: persisted query no longer known');
    }
    if (data == null) throw ApiChanged(_site, '$what: ${messages.join('; ')}');
  }

  /// The `data` of one envelope after [_errors].
  static Map<String, dynamic> _data(Object? envelope, String what) {
    final map = _map(envelope, what);
    final data = map['data'];
    _errors(map, what, data: data);
    return _map(data, '$what.data');
  }

  /// A batched request answers with a list; a single one with an object.
  static List<Object?> _envelopes(String body, String what) => switch (_json(body, what)) {
    final List<Object?> list => list,
    final Map<String, dynamic> map => [map],
    _ => throw ApiChanged(_site, '$what: not an envelope'),
  };

  static Uri? _image(Object? value, {int width = 440, int height = 248}) {
    final text = jsonString(value);
    if (text == null) return null;
    return jsonUrl(text.replaceAll('{width}', '$width').replaceAll('{height}', '$height'));
  }

  static LiveState _state(Object? stream) {
    if (stream is! Map) return LiveState.offline;
    return switch (jsonString(stream['type'])) {
      'rerun' => LiveState.replay,
      _ => LiveState.live,
    };
  }

  static String? _name(Object? value) {
    final text = jsonString(value)?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// §2.1 `SearchCategoryTags`: the genre tags, in the server's order; a
  /// tag without a name in either field is left out.
  static List<TwitchTag> tags(String body) {
    final data = _data(_envelopes(body, 'SearchCategoryTags').first, 'SearchCategoryTags');
    final list = data['searchCategoryTags'];
    if (list is! List) throw const ApiChanged(_site, 'SearchCategoryTags: no list');
    return [
      for (final tag in list)
        if (tag is Map)
          if ((jsonString(tag['id']), _name(tag['localizedName']) ?? _name(tag['tagName'])) case (
            final String id,
            final String name,
          ))
            (id: id, name: name),
    ];
  }

  /// §2.1 one `BrowsePage_AllDirectories` envelope: the directories as areas
  /// of [categoryId]; the area id is the directory slug.
  static List<Area> directories(Object? envelope, {required String categoryId}) {
    final data = _data(envelope, 'BrowsePage_AllDirectories');
    final connection = data['directoriesWithTags'];
    final edges = connection is Map ? connection['edges'] : null;
    return [
      for (final edge in edges is List ? edges : const [])
        if (edge is Map && edge['node'] is Map)
          if ((jsonString((edge['node'] as Map)['slug']), jsonString((edge['node'] as Map)['displayName'])) case (
            final String slug,
            final String name,
          ))
            Area(id: slug, name: name, categoryId: categoryId, icon: _image((edge['node'] as Map)['avatarURL'])),
    ];
  }

  /// The envelopes of a batched response, in request order.
  static List<Object?> batch(String body, {required int expected}) {
    final envelopes = _envelopes(body, 'batch');
    if (envelopes.length != expected) {
      throw ApiChanged(_site, 'batch: ${envelopes.length} answers for $expected operations');
    }
    return envelopes;
  }

  static RoomCard? _streamCard(Map<dynamic, dynamic> node, {Map<dynamic, dynamic>? game}) {
    final broadcaster = node['broadcaster'];
    if (broadcaster is! Map) return null;
    final login = jsonString(broadcaster['login'])?.toLowerCase();
    if (login == null || !isLogin(login)) return null;
    final area = node['game'] is Map ? node['game'] as Map : game;
    final created = DateTime.tryParse(jsonString(node['createdAt']) ?? '');
    return RoomCard(
      ref: RoomRef(_site, login),
      title: jsonString(node['title']) ?? '',
      anchorName: jsonString(broadcaster['displayName']) ?? login,
      state: _state(node),
      cover: _image(node['previewImageURL']),
      area: area == null ? null : jsonString(area['displayName']) ?? jsonString(area['name']),
      audience: Audience(online: jsonInt(node['viewersCount'])),
      liveSince: created?.toUtc(),
      avatar: _image(broadcaster['profileImageURL']),
    );
  }

  static List<RoomCard> _streamEdges(Object? connection, {Map<dynamic, dynamic>? game}) {
    final edges = connection is Map ? connection['edges'] : null;
    return [
      for (final edge in edges is List ? edges : const [])
        if (edge is Map && edge['node'] is Map) ?_streamCard(edge['node'] as Map, game: game),
    ];
  }

  /// §2.2 `DirectoryPage_Game`: the first page of a directory's streams;
  /// `game == null` is an unknown directory. Later pages need an integrity
  /// token (§8), so the page is the last one.
  static Page<RoomCard> gameStreams(String body, {required String slug}) {
    final data = _data(_envelopes(body, 'DirectoryPage_Game').first, 'DirectoryPage_Game');
    final game = data['game'];
    if (game is! Map) throw NotFound(_site, 'no directory $slug');
    return Page(_streamEdges(game['streams'], game: game));
  }

  /// §2.3 the raw `streams` query: the busiest live streams of the site.
  static Page<RoomCard> streams(String body) {
    final data = _data(_envelopes(body, 'streams').first, 'streams');
    return Page(_streamEdges(data['streams']));
  }

  /// §3 `SearchResultsPage_SearchResults`: channels, live or not; the next
  /// page is `channels.cursor`, empty at the end.
  static Page<RoomCard> searchPage(String body) {
    final data = _data(_envelopes(body, 'SearchResultsPage_SearchResults').first, 'SearchResultsPage_SearchResults');
    final search = _map(data['searchFor'], 'searchFor');
    final channels = search['channels'];
    if (channels is! Map) return const Page.empty();
    final rooms = <RoomCard>[];
    final edges = channels['edges'];
    for (final edge in edges is List ? edges : const []) {
      final item = edge is Map ? edge['item'] : null;
      if (item is! Map) continue;
      final login = jsonString(item['login'])?.toLowerCase();
      if (login == null || !isLogin(login)) continue;
      final stream = item['stream'];
      final live = stream is Map;
      final settings = item['broadcastSettings'];
      final game = live ? stream['game'] : null;
      rooms.add(
        RoomCard(
          ref: RoomRef(_site, login),
          title: settings is Map ? jsonString(settings['title']) ?? '' : '',
          anchorName: jsonString(item['displayName']) ?? login,
          state: _state(stream),
          cover: live ? _image(stream['templatePreviewImageURL']) ?? _image(stream['previewImageURL']) : null,
          area: game is Map ? jsonString(game['displayName']) ?? jsonString(game['name']) : null,
          audience: live ? Audience(online: jsonInt(stream['viewersCount'])) : Audience.none,
          avatar: _image(item['profileImageURL']),
          followers: switch (item['followers']) {
            final Map<dynamic, dynamic> followers => jsonCount(followers['totalCount']),
            _ => null,
          },
        ),
      );
    }
    final cursor = jsonString(channels['cursor']);
    return Page(rooms, next: rooms.isNotEmpty && cursor != null ? PageCursor(cursor) : null);
  }

  /// §4 the raw `user` query: `user == null` is an unknown login.
  static RoomDetail detail(String body, {required String login}) {
    final data = _data(_envelopes(body, 'user').first, 'user');
    final user = data['user'];
    if (user is! Map) throw NotFound(_site, 'no channel $login');
    final answered = jsonString(user['login'])?.toLowerCase();
    if (answered != login) throw ApiChanged(_site, 'user answered $answered for $login');
    final stream = user['stream'];
    final live = stream is Map;
    final last = user['lastBroadcast'];
    final game = live ? stream['game'] : (last is Map ? last['game'] : null);
    final created = live ? DateTime.tryParse(jsonString(stream['createdAt']) ?? '') : null;
    final avatar = _image(user['profileImageURL']);
    final description = jsonString(user['description'])?.trim();
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, login),
        title: (live ? jsonString(stream['title']) : null) ?? (last is Map ? jsonString(last['title']) : null) ?? '',
        anchorName: jsonString(user['displayName']) ?? login,
        state: _state(stream),
        cover: live ? _image(stream['previewImageURL']) : null,
        area: game is Map ? jsonString(game['displayName']) ?? jsonString(game['name']) : null,
        audience: live ? Audience(online: jsonInt(stream['viewersCount'])) : Audience.none,
        liveSince: created?.toUtc(),
        avatar: avatar,
      ),
      link: Uri.parse('https://www.twitch.tv/$login'),
      avatar: avatar,
      introduction: description == null || description.isEmpty ? null : description,
      danmakuKeys: {'login': login, 'channelId': ?jsonString(user['id'])},
    );
  }

  /// §6.1 `PlaybackAccessToken`: null token is an unknown login; the
  /// token's own `authorization` says whether this viewer may watch.
  static TwitchAccessToken accessToken(String body, {required String login}) {
    final data = _data(_envelopes(body, 'PlaybackAccessToken').first, 'PlaybackAccessToken');
    final token = data['streamPlaybackAccessToken'];
    if (token is! Map) throw NotFound(_site, 'no channel $login');
    final value = jsonString(token['value']);
    final signature = jsonString(token['signature']);
    if (value == null || signature == null) throw const ApiChanged(_site, 'PlaybackAccessToken: incomplete');
    Object? claims;
    try {
      claims = jsonDecode(value);
    } on FormatException {
      claims = null;
    }
    if (claims is Map) {
      final authorization = claims['authorization'];
      if (authorization is Map && authorization['forbidden'] == true) {
        final reason = jsonString(authorization['reason']) ?? '';
        if (reason.toLowerCase().contains('geo')) throw RegionBlocked(_site, 'PlaybackAccessToken: $reason');
        throw NeedsLogin(_site, 'PlaybackAccessToken: $reason');
      }
    }
    return (value: value, signature: signature);
  }

  /// §6.2 the usher master playlist of [login].
  static Uri usherUrl(String login, TwitchAccessToken token, {required int nonce}) =>
      Uri.https('usher.ttvnw.net', '/api/channel/hls/$login.m3u8', {
        'allow_source': 'true',
        'fast_bread': 'true',
        'p': '$nonce',
        'platform': 'web',
        'player_backend': 'mediaplayer',
        'playlist_include_framerate': 'true',
        'reassignments_supported': 'true',
        'supported_codecs': 'avc1',
        'cdm': 'wv',
        'sig': token.signature,
        'token': token.value,
      });

  /// §6.2 the usher answer: 404 is a channel that is not broadcasting; 403
  /// names why this viewer may not watch.
  static void usherStatus(int status, String body) {
    if (status == 200) return;
    if (status >= 500) throw NetworkFailure(_site, 'usher HTTP $status');
    String? code;
    String? message;
    final json = body.trimLeft().startsWith('[') || body.trimLeft().startsWith('{') ? _json(body, 'usher') : null;
    final first = json is List && json.isNotEmpty ? json.first : json;
    if (first is Map) {
      code = jsonString(first['error_code']);
      message = jsonString(first['error']);
    }
    final detail = 'usher HTTP $status ${code ?? ''} ${message ?? ''}'.trim();
    if (status == 404) throw StreamUnavailable(_site, detail);
    if (status == 403) {
      if ('$code $message'.toLowerCase().contains('geo')) throw RegionBlocked(_site, detail);
      throw NeedsLogin(_site, detail);
    }
    throw ApiChanged(_site, detail);
  }

  static final _attribute = RegExp('([A-Z0-9-]+)=("[^"]*"|[^,]*)');

  static Map<String, String> _attributes(String text) => {
    for (final match in _attribute.allMatches(text))
      match.group(1)!: match.group(2)!.startsWith('"') && match.group(2)!.length >= 2
          ? match.group(2)!.substring(1, match.group(2)!.length - 1)
          : match.group(2)!,
  };

  /// §5 the master playlist: one variant per `VIDEO` group, named by its
  /// `EXT-X-MEDIA`; the source (`chunked`) first, then by bandwidth; audio
  /// only is left out.
  static List<TwitchVariant> master(String body, {required Uri base}) {
    if (!body.trimLeft().startsWith('#EXTM3U')) throw const ApiChanged(_site, 'usher: not a playlist');
    final names = <String, String>{};
    final found = <({String group, String label, int bandwidth, bool source, Uri url, String? codec})>[];
    Map<String, String>? pending;
    for (final raw in const LineSplitter().convert(body)) {
      final line = raw.trim();
      if (line.startsWith('#EXT-X-MEDIA:')) {
        final media = _attributes(line.substring('#EXT-X-MEDIA:'.length));
        final group = media['GROUP-ID'];
        final name = media['NAME'];
        if (group != null && name != null) names[group] = name;
      } else if (line.startsWith('#EXT-X-STREAM-INF:')) {
        pending = _attributes(line.substring('#EXT-X-STREAM-INF:'.length));
      } else if (line.isNotEmpty && !line.startsWith('#') && pending != null) {
        final attributes = pending;
        pending = null;
        final group = attributes['VIDEO'] ?? '';
        final url = base.resolve(line);
        if (group.isEmpty || group == 'audio_only' || (url.scheme != 'https' && url.scheme != 'http')) continue;
        final codecs = attributes['CODECS'] ?? '';
        found.add((
          group: group,
          label: names[group] ?? group,
          bandwidth: int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0,
          source: group == 'chunked',
          url: url,
          codec: codecs.contains('avc1')
              ? 'avc'
              : codecs.contains('hev1') || codecs.contains('hvc1')
              ? 'hevc'
              : codecs.contains('av01')
              ? 'av1'
              : null,
        ));
      }
    }
    if (found.isEmpty) throw const StreamUnavailable(_site, 'usher: no video variant');
    final seen = <String>{};
    final unique = [
      for (final variant in found)
        if (seen.add(variant.group)) variant,
    ]..sort((a, b) => a.source != b.source ? (a.source ? -1 : 1) : b.bandwidth.compareTo(a.bandwidth));
    return [
      for (final (index, variant) in unique.indexed)
        (
          quality: Quality(id: variant.group, label: variant.label, rank: unique.length - index),
          url: variant.url,
          codec: variant.codec,
        ),
    ];
  }
}
