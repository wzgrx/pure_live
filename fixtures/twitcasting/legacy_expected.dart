// Writes expected.json for the TwitCasting samples: 3.x's parsers run over
// the recorded responses (docs/modules/M4.12-twitcasting.md, "样本与 v3 的冻结
// 输出").
//
// The archive has no TwitCasting expected.json (its legacy harness only
// covered five platforms, and 3.x no longer builds). The parsing below is
// 3.x's code, copied from legacy/lib/core/site/twitcasting/twitcasting_api.dart
// and twitcasting_site.dart (archive/v4) with only the transport replaced:
// `_replay` answers from the samples by host, path and `target`, follows a
// recorded redirect the way 3.x's Dio did (at most five hops), and throws a
// StateError for a request without a sample. `_LegacyRoom` and
// `_LegacyQuality` are the parts of 3.x's LiveRoom and LivePlayQuality these
// parsers use. The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`).
//
// 3.x parsed the pages with package:html, which the workspace does not
// depend on, so this runs with a throwaway package configuration. From the
// repository root:
//
//   d=$(mktemp -d)
//   printf 'name: g\nenvironment:\n  sdk: ^3.9.0\ndependencies:\n  html: 0.15.6\n' > "$d/pubspec.yaml"
//   (cd "$d" && dart pub get)
//   dart --packages="$d/.dart_tool/package_config.json" fixtures/twitcasting/legacy_expected.dart
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;

const _root = 'fixtures/twitcasting';

void main() async {
  await _categories();
  await _recommend();
  await _areaRooms();
  await _search();
  await _detail('S04-page-live', 'S05-stream-live', 'nabo66game');
  await _detail('S04-page-offline', 'S05-stream-offline', 'twitcasting_jp');
  await _detail('S04-page-notfound', 'S05-stream-notfound', 'zxqvnochannelfixture');
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];

/// Applied to every replayed body (identity except where a sample says).
String Function(String body) _edit = _unchanged;

String _unchanged(String body) => body;

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _load(List<String> samples, {String Function(String body) edit = _unchanged}) {
  _samples = [for (final sample in samples) _meta(sample)];
  _edit = edit;
}

/// 3.x's `_defaultRequest` over the samples: Dio followed redirects and read
/// the final body.
Future<({int status, String body})> _replay(Uri uri, Object? cancel) async {
  var current = uri;
  for (var hop = 0; hop <= 5; hop++) {
    final meta = _samples.firstWhere((meta) {
      final recorded = Uri.parse((meta['request'] as Map)['url'] as String);
      return recorded.host == current.host &&
          recorded.path == current.path &&
          recorded.queryParameters['target'] == current.queryParameters['target'];
    }, orElse: () => throw StateError('No recorded sample for GET $current'));
    final response = meta['response'] as Map<String, dynamic>;
    final status = response['status'] as int;
    final location = (response['headers'] as Map<String, dynamic>)['location'];
    if ({301, 302, 303, 307, 308}.contains(status) && location is String) {
      current = current.resolve(location);
      continue;
    }
    final body = _edit(File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync());
    return (status: status, body: status == 200 ? body : '');
  }
  throw StateError('Too many redirects for $uri');
}

void _write(String sample, String generator, Object? value) {
  final file = File('$_root/$sample/expected.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'generator': generator, 'value': jsonDecode(jsonEncode(value))})}\n',
  );
  stdout.writeln('wrote $sample');
}

Map<String, dynamic> _errorProjection(Object error) => {
  'throws': error.runtimeType.toString(),
  'message': error.toString(),
};

Future<Object?> _outcome<T>(Future<T> Function() body, Object? Function(T value) project) async {
  try {
    return project(await body());
  } on Object catch (error) {
    return _errorProjection(error);
  }
}

Map<String, dynamic> _roomProjection(_LegacyRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere(
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(List<_LegacyRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

// Samples ---------------------------------------------------------------------

Future<void> _categories() async {
  _load(['S01-home']);
  final site = TwitcastingSite(api: TwitcastingApi(request: _replay));
  _write('S01-home', 'TwitcastingSite.getCategores (pages 1 and 2)', {
    'page1': await _outcome(
      () => site.getCategores(1, 30),
      (categories) => [
        for (final category in categories)
          {
            'id': category.id,
            'name': category.name,
            'children': [for (final area in category.children) area.toJson()],
          },
      ],
    ),
    'page2': await _outcome(() => site.getCategores(2, 30), (categories) => categories.length),
  });
}

/// The popular page's request (3.x's `PopularServerFixedController`, fixed
/// size 60), its second window, and the adapter's own slices of 20.
Future<void> _recommend() async {
  _load(['S02-top-all']);
  final site = TwitcastingSite(api: TwitcastingApi(request: _replay));
  _write('S02-top-all', 'TwitcastingSite.getRecommendRooms', {
    'page1size60': await _outcome(() => site.getRecommendRooms(page: 1, pageSize: 60), _rooms),
    'page2size60': await _outcome(() => site.getRecommendRooms(page: 2, pageSize: 60), _rooms),
    'size20': [
      for (final page in [1, 2, 3, 4])
        await _outcome(
          () => site.getRecommendRooms(page: page, pageSize: 20),
          (rooms) => [for (final room in rooms) room.roomId],
        ),
    ],
  });
}

/// The area page's request (3.x's `AreaServerFixedController`, fixed size
/// 60) for the "Game" tab.
Future<void> _areaRooms() async {
  _load(['S02-top-game']);
  final site = TwitcastingSite(api: TwitcastingApi(request: _replay));
  final area = _LegacyArea(
    platform: 'twitcasting',
    areaType: 'directory',
    typeName: 'TwitCasting',
    areaId: '_system_channel_12',
    areaName: 'Game',
  );
  _write('S02-top-game', 'TwitcastingSite.getCategoryRooms', {
    'page1size60': await _outcome(() => site.getCategoryRooms(area, page: 1, pageSize: 60), _rooms),
    'page2size60': await _outcome(() => site.getCategoryRooms(area, page: 2, pageSize: 60), _rooms),
  });
}

/// The search page's requests (`pageSize: 20`, 3.x's search controller).
///
/// The recorded live section holds a private broadcast (no LIVE badge,
/// `data-can-play="false"`), which 3.x rejects as schema drift, failing the
/// whole page. `withoutPrivateRow` is 3.x's answer to the same page with
/// that one row cut out: the field-by-field reference for the other rows.
Future<void> _search() async {
  final site = TwitcastingSite(api: TwitcastingApi(request: _replay));
  final value = <String, Object?>{};
  _load(['S03-search']);
  for (final page in [1, 2, 3, 4]) {
    value['page$page'] = await _outcome(() => site.searchRooms('game', page: page, pageSize: 20), _rooms);
  }
  _load(['S03-search'], edit: _withoutPrivateRow);
  value['withoutPrivateRow'] = await _outcome(() => site.searchRooms('game', page: 1, pageSize: 20), _rooms);
  _write('S03-search', 'TwitcastingSite.searchRooms (pageSize 20)', value);
}

/// [body] without the search row of the private broadcast
/// `/g:107135074068699391720/movie/841524002`.
String _withoutPrivateRow(String body) {
  const row = '<div class="tw-search-result-row">';
  final link = body.indexOf('href="/g:107135074068699391720/movie/841524002"');
  if (link < 0) throw StateError('the private row is not in the sample');
  final start = body.lastIndexOf(row, link);
  final end = body.indexOf(row, link);
  return body.replaceRange(start, end, '');
}

Future<void> _detail(String page, String stream, String roomId) async {
  _load([page, stream, 'S01-home']);
  final site = TwitcastingSite(api: TwitcastingApi(request: _replay));
  final value = <String, Object?>{
    'getRoomDetail': await _outcome(() => site.getRoomDetail(roomId: roomId, platform: 'twitcasting'), _roomProjection),
    'getRoomDetailForRefresh': await _outcome(
      () => site.getRoomDetailForRefresh(roomId: roomId, platform: 'twitcasting'),
      _roomProjection,
    ),
    'searchRooms(link)': await _outcome(() => site.searchRooms('https://twitcasting.tv/$roomId'), _rooms),
  };
  try {
    final detail = await site.getRoomDetail(roomId: roomId, platform: 'twitcasting');
    value['getPlayQualites'] = [
      for (final quality in await site.getPlayQualites(detail: detail))
        {
          'quality': quality.quality,
          'id': quality.id,
          'sort': quality.sort,
          'getPlayUrls': await site.getPlayUrls(detail: detail, quality: quality),
        },
    ];
  } on Object catch (error) {
    value['getPlayQualites'] = _errorProjection(error);
  }
  _write(
    page,
    'TwitcastingSite.getRoomDetail + getRoomDetailForRefresh + searchRooms(link) + getPlayQualites + getPlayUrls '
    '(with $stream)',
    value,
  );
}

// 3.x models (the parts the TwitCasting parsers use) -------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

class _LegacyArea {
  _LegacyArea({this.platform, this.areaType, this.typeName, this.areaId, this.areaName, this.areaPic, this.shortName});

  String? platform;
  String? areaType;
  String? typeName;
  String? areaId;
  String? areaName;
  String? areaPic;
  String? shortName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'platform': platform,
    'areaType': areaType,
    'typeName': typeName,
    'areaId': areaId,
    'areaName': areaName,
    'areaPic': areaPic,
    'shortName': shortName,
  };
}

class _LegacyCategory {
  _LegacyCategory({required this.id, required this.name, required this.children});

  final String name;
  final String id;
  final List<_LegacyArea> children;
}

class _LegacyQuality {
  _LegacyQuality({required this.quality, this.data, this.id, this.sort = 0});

  final String quality;
  final dynamic data;
  final Object? id;
  final int sort;

  Object get selectionId => id ?? quality;
}

class _LegacyRoom {
  _LegacyRoom({
    this.roomId,
    this.userId,
    this.link,
    this.title = '',
    this.nick = '',
    this.avatar = '',
    this.cover = '',
    this.area,
    this.watching = '0',
    this.audienceMetricType,
    this.popularity = '',
    this.onlineViewers = '',
    this.totalViewers = '',
    this.followers = '0',
    this.platform,
    LiveStatus? liveStatus,
    this.data,
    this.danmakuData,
    this.isRecord = false,
    this.status = false,
    this.notice,
    this.introduction,
  }) : liveStatus = liveStatus ?? _legacyStatusToLiveStatus(status: status, isRecord: isRecord);

  String? roomId;
  String? userId;
  String? link;
  String? title;
  String? nick;
  String? avatar;
  String? cover;
  String? area;
  String? watching;
  AudienceMetricType? audienceMetricType;
  String? popularity;
  String? onlineViewers;
  String? totalViewers;
  String? followers;
  String? platform;
  String? introduction;
  String? notice;
  bool? status;
  dynamic data;
  dynamic danmakuData;
  bool? isRecord;
  LiveStatus? liveStatus;

  static LiveStatus? _legacyStatusToLiveStatus({required bool? status, required bool? isRecord}) {
    if (isRecord == true) return LiveStatus.replay;
    if (status == true) return LiveStatus.live;
    if (status == false) return LiveStatus.offline;
    return null;
  }

  String get normalizedPlatformId => (platform ?? '').trim().toLowerCase();

  LiveStatus get effectiveLiveStatus {
    if (isRecord == true || liveStatus == LiveStatus.replay) return LiveStatus.replay;
    final canonical = liveStatus;
    if (canonical != null) return canonical;
    return _legacyStatusToLiveStatus(status: status, isRecord: isRecord) ?? LiveStatus.unknown;
  }

  bool get isLiveNow => effectiveLiveStatus == LiveStatus.live;

  bool get isPlayableNow => isLiveNow || effectiveLiveStatus == LiveStatus.replay;

  bool get isExplicitlyOfflineNow =>
      effectiveLiveStatus == LiveStatus.offline || effectiveLiveStatus == LiveStatus.banned;

  AudienceMetricType get effectiveAudienceMetricType {
    if (audienceMetricType != null && audienceMetricType != AudienceMetricType.unknown) return audienceMetricType!;
    return switch (normalizedPlatformId) {
      'bilibili' || 'douyu' || 'huya' || 'cc' || 'yy' || 'missevan' => AudienceMetricType.popularity,
      'kuaishou' || 'twitch' || 'soop' => AudienceMetricType.onlineViewers,
      'douyin' => AudienceMetricType.totalViewers,
      _ => AudienceMetricType.unknown,
    };
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'roomId': roomId,
    'userId': userId,
    'title': title,
    'nick': nick,
    'avatar': avatar,
    'cover': cover,
    'area': area,
    'watching': watching,
    'audienceMetricType': effectiveAudienceMetricType.name,
    'popularity': popularity,
    'onlineViewers': onlineViewers,
    'totalViewers': totalViewers,
    'followers': followers,
    'platform': platform,
    'tagIds': <String>[],
    'liveStatus': effectiveLiveStatus.index,
    'isRecord': isRecord,
    'status': isLiveNow,
    'notice': notice,
    'introduction': introduction,
    'isCatchUp': false,
    'httpHeaders': <String, String>{},
  };
}

// 3.x's TwitCasting adapter (legacy/lib/core/site/twitcasting/) ---------------
//
// Unchanged apart from the model names above and the transport: no Dio, so
// `CancelToken` is `Object?` and `_defaultRequest` / `readBody` (the streamed
// 1 MiB body reader) are left out; `read` keeps the same status and size
// checks, and lets the harness's StateError (a request without a sample)
// through instead of reporting it as a transport failure.

enum TwitcastingFailure { transport, access, rateLimited, service, notFound, schema, cancelled, qualityUnavailable }

class TwitcastingException implements Exception {
  const TwitcastingException(this.kind);
  final TwitcastingFailure kind;
  @override
  String toString() => 'TwitCasting ${kind.name}';
}

typedef TwitcastingRequest = Future<({int status, String body})> Function(Uri uri, Object? cancel);

class TwitcastingApi {
  TwitcastingApi({required TwitcastingRequest request}) : _request = request;
  static const origin = 'https://twitcasting.tv';
  static const directoryOrigin = 'https://frontendapi.twitcasting.tv';
  static const directoryWindow = 60;
  static const searchWindow = 50;
  static const responseLimit = 1024 * 1024;
  static const playHeaders = <String, String>{'Referer': '$origin/', 'Origin': origin, 'User-Agent': 'Mozilla/5.0'};
  final TwitcastingRequest _request;

  Future<String> read(Uri uri, {Object? cancel}) async {
    late final ({int status, String body}) response;
    try {
      response = await _request(uri, cancel);
    } catch (error) {
      if (error is TwitcastingException) rethrow;
      if (error is StateError) rethrow;
      throw const TwitcastingException(TwitcastingFailure.transport);
    }
    final failure = switch (response.status) {
      200 => null,
      401 || 403 => TwitcastingFailure.access,
      404 => TwitcastingFailure.notFound,
      429 => TwitcastingFailure.rateLimited,
      >= 500 => TwitcastingFailure.service,
      _ => TwitcastingFailure.transport,
    };
    if (failure != null) throw TwitcastingException(failure);
    if (response.body.length > responseLimit || utf8.encode(response.body).length > responseLimit) {
      throw const TwitcastingException(TwitcastingFailure.schema);
    }
    return response.body;
  }

  static Map<String, dynamic> object(Object? raw) {
    if (raw is String) {
      if (raw.length > responseLimit || utf8.encode(raw).length > responseLimit) {
        throw const TwitcastingException(TwitcastingFailure.schema);
      }
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        throw const TwitcastingException(TwitcastingFailure.schema);
      }
    }
    if (raw is! Map || raw.keys.any((key) => key is! String)) {
      throw const TwitcastingException(TwitcastingFailure.schema);
    }
    return Map<String, dynamic>.from(raw);
  }

  static String text(Object? raw) => raw is String ? raw.trim() : '';
  static int? integer(Object? raw) => raw is int ? raw : (raw is String ? int.tryParse(raw) : null);
  static String picture(Object? raw) {
    var value = text(raw);
    if (value.startsWith('//')) value = 'https:$value';
    final uri = Uri.tryParse(value);
    return uri != null && {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty && uri.userInfo.isEmpty
        ? value
        : '';
  }

  static String channelName(String value) {
    final name = value.trim().toLowerCase();
    if (!RegExp(r'^(?:(?:c|g|f|ig):)?[a-z0-9_]{1,64}$').hasMatch(name) ||
        const {
          'search',
          'help',
          'login',
          'logout',
          'settings',
          'signup',
          'register',
          'terms',
          'privacy',
          'about',
          'index',
          'show',
          'categories',
        }.contains(name)) {
      throw const TwitcastingException(TwitcastingFailure.schema);
    }
    return name;
  }

  static String? channelFromUri(Uri uri) {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        !{'twitcasting.tv', 'www.twitcasting.tv'}.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    try {
      final parts = uri.pathSegments.toList();
      if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
      return parts.length == 1 ? channelName(parts.single) : null;
    } on FormatException {
      return null;
    } on TwitcastingException {
      return null;
    }
  }

  Future<List<_LegacyArea>> categories({Object? cancel}) async {
    final document = html.parse(await read(Uri.parse('$origin/'), cancel: cancel));
    final result = <String, _LegacyArea>{};
    for (final element in document.querySelectorAll('a.tw-top-tab-item[data-channel]')) {
      final key = element.attributes['data-channel'] ?? '';
      if (!RegExp(r'^[a-zA-Z0-9_]{1,80}$').hasMatch(key) || element.text.trim().isEmpty) {
        throw const TwitcastingException(TwitcastingFailure.schema);
      }
      result.putIfAbsent(
        key,
        () => _LegacyArea(
          platform: 'twitcasting',
          areaId: key,
          areaType: 'directory',
          areaName: element.text.trim(),
          typeName: 'TwitCasting',
        ),
      );
    }
    if (result.isEmpty || result.length > 100) throw const TwitcastingException(TwitcastingFailure.schema);
    return List.unmodifiable(result.values);
  }

  Future<List<_LegacyRoom>> directory({int page = 1, int pageSize = 30, String category = '', Object? cancel}) async {
    if (page < 1 ||
        page > 10000 ||
        pageSize < 1 ||
        pageSize > directoryWindow ||
        (category.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_]{1,80}$').hasMatch(category))) {
      throw const TwitcastingException(TwitcastingFailure.schema);
    }
    final offset = (page - 1) * pageSize;
    if (offset >= directoryWindow) return const [];
    final uri = Uri.parse('$directoryOrigin/top/category')
        .replace(queryParameters: {'id': category, 'count': '$directoryWindow'});
    final data = object(await read(uri, cancel: cancel));
    final rows = data['movies'];
    if (rows is! List || rows.length > directoryWindow) throw const TwitcastingException(TwitcastingFailure.schema);
    final rooms = <String, _LegacyRoom>{};
    for (final raw in rows.skip(offset).take(pageSize)) {
      final row = object(raw);
      for (final flag in ['is_live', 'is_locked', 'is_group', 'is_deleted']) {
        if (row[flag] is! bool) throw const TwitcastingException(TwitcastingFailure.schema);
      }
      if (row['is_live'] != true ||
          row['is_locked'] != false ||
          row['is_group'] != false ||
          row['is_deleted'] != false) {
        continue;
      }
      final channel = channelName(text(row['user_id']));
      final movie = integer(row['id']);
      final link = Uri.tryParse(text(row['live_url']));
      if (movie == null ||
          movie <= 0 ||
          link == null ||
          link.hasAuthority ||
          link.hasQuery ||
          link.hasFragment ||
          link.pathSegments.join('/') != '$channel/movie/$movie') {
        throw const TwitcastingException(TwitcastingFailure.schema);
      }
      final count = integer(row['current_viewer_count']);
      if (count == null || count < 0) throw const TwitcastingException(TwitcastingFailure.schema);
      rooms.putIfAbsent(
        channel,
        () => _LegacyRoom(
          platform: 'twitcasting',
          roomId: channel,
          userId: channel,
          title: text(row['telop']).isNotEmpty ? text(row['telop']) : text(row['title']),
          nick: text(row['user_name']),
          cover: picture(row['thumbnail_url']),
          avatar: picture(row['user_icon_url']),
          link: '$origin/$channel',
          watching: '$count',
          onlineViewers: '$count',
          audienceMetricType: AudienceMetricType.onlineViewers,
          status: true,
          liveStatus: LiveStatus.live,
        ),
      );
    }
    return List.unmodifiable(rooms.values);
  }

  Future<List<_LegacyRoom>> searchLives(String keyword, {int page = 1, int pageSize = 20, Object? cancel}) async {
    final query = keyword.trim();
    if (page < 1 || page > 10000 || pageSize < 1 || pageSize > searchWindow || query.length > 100) {
      throw const TwitcastingException(TwitcastingFailure.schema);
    }
    if (query.isEmpty || (page - 1) * pageSize >= searchWindow) return const [];
    final inputUri = Uri.tryParse(query);
    if (inputUri != null && {'twitcasting.tv', 'www.twitcasting.tv'}.contains(inputUri.host.toLowerCase())) {
      final channel = channelFromUri(inputUri);
      if (channel == null || page != 1) return const [];
      try {
        return [await detail(channel, includeMedia: false, cancel: cancel)];
      } on TwitcastingException catch (error) {
        if (error.kind == TwitcastingFailure.notFound) return const [];
        rethrow;
      }
    }
    final uri = Uri(
      scheme: 'https',
      host: 'search.twitcasting.tv',
      pathSegments: ['search', 'text', query],
      queryParameters: {'hl': 'en'},
    );
    final document = html.parse(await read(uri, cancel: cancel));
    final section = document.querySelector('#tw-search-result-live');
    if (section == null) throw const TwitcastingException(TwitcastingFailure.schema);
    final rows = section.querySelectorAll('.tw-search-result-row');
    if (rows.length > searchWindow) throw const TwitcastingException(TwitcastingFailure.schema);
    final rooms = <String, _LegacyRoom>{};
    for (final row in rows.skip((page - 1) * pageSize).take(pageSize)) {
      final movieHref = row.querySelector('a.tw-movie-thumbnail2')?.attributes['href'] ?? '';
      final channelHref = row.querySelector('.tw-search-result-row-user-name .usertext a')?.attributes['href'] ?? '';
      final movieUri = Uri.tryParse(movieHref);
      final channelUri = Uri.tryParse(channelHref);
      if (movieUri == null ||
          channelUri == null ||
          movieUri.hasAuthority ||
          channelUri.hasAuthority ||
          movieUri.hasQuery ||
          movieUri.hasFragment ||
          channelUri.hasQuery ||
          channelUri.hasFragment ||
          channelUri.pathSegments.length != 1 ||
          movieUri.pathSegments.length != 3 ||
          row.querySelector('.tw-movie-thumbnail2-badge[data-status="live"]') == null ||
          row.querySelector('.tw-movie-thumbnail2-image-wrapper[data-can-play="true"]') == null) {
        throw const TwitcastingException(TwitcastingFailure.schema);
      }
      final channel = channelName(channelUri.pathSegments.single);
      final movie = integer(movieUri.pathSegments.last);
      if (movieUri.pathSegments[0].toLowerCase() != channel ||
          movieUri.pathSegments[1] != 'movie' ||
          movie == null ||
          movie <= 0) {
        throw const TwitcastingException(TwitcastingFailure.schema);
      }
      rooms.putIfAbsent(
        channel,
        () => _LegacyRoom(
          platform: 'twitcasting',
          roomId: channel,
          userId: channel,
          link: '$origin/$channel',
          title: row.querySelector('.tw-movie-thumbnail-title')?.text.trim() ?? '',
          nick: row.querySelector('.tw-search-result-row-user-name .username')?.text.trim() ?? channel,
          cover: picture(row.querySelector('.tw-movie-thumbnail2-image')?.attributes['src']),
          avatar: picture(row.querySelector('.userimage32 img')?.attributes['src']),
          watching: '',
          audienceMetricType: AudienceMetricType.unknown,
          status: true,
          liveStatus: LiveStatus.live,
        ),
      );
    }
    return List.unmodifiable(rooms.values);
  }

  Future<_LegacyRoom> detail(String input, {bool includeMedia = true, Object? cancel}) async {
    final channel = channelName(input);
    final page = await read(Uri.parse('$origin/$channel'), cancel: cancel);
    if (page.contains('Enter the secret word to access')) throw const TwitcastingException(TwitcastingFailure.access);
    final document = html.parse(page);
    final creators = document.querySelectorAll('meta[name="twitter:creator"]');
    if (creators.length != 1 || channelName(creators.single.attributes['content'] ?? '') != channel) {
      throw const TwitcastingException(TwitcastingFailure.schema);
    }
    final header = document.querySelector('.tw-user-header');
    if (header == null || channelName(header.attributes['data-user-id'] ?? '') != channel) {
      throw const TwitcastingException(TwitcastingFailure.schema);
    }
    final stream = object(
      await read(
        Uri.parse('$origin/streamserver.php')
            .replace(queryParameters: {'target': channel, 'mode': 'client', 'player': 'pc_web'}),
        cancel: cancel,
      ),
    );
    final movie = object(stream['movie']);
    if (movie['live'] is! bool) throw const TwitcastingException(TwitcastingFailure.schema);
    final live = movie['live'] == true;
    final room = _LegacyRoom(
      platform: 'twitcasting',
      roomId: channel,
      userId: channel,
      link: '$origin/$channel',
      title: document.querySelector('meta[name="twitter:title"]')?.attributes['content'] ?? '',
      nick: document.querySelector('.tw-user-nav2-name')?.text.trim() ?? channel,
      avatar: picture(document.querySelector('.tw-user-nav2-icon img')?.attributes['src']),
      cover: picture(document.querySelector('meta[property="og:image"]')?.attributes['content']),
      watching: '',
      status: live,
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
    );
    if (!live || !includeMedia) {
      room.data = const <_LegacyQuality>[];
      return room;
    }
    final movieId = integer(movie['id']);
    if (movieId == null || movieId <= 0) throw const TwitcastingException(TwitcastingFailure.schema);
    final streams = object(object(stream['tc-hls'])['streams']);
    final qualities = <_LegacyQuality>[];
    for (final key in ['high', 'medium', 'low']) {
      if (!streams.containsKey(key)) continue;
      final url = text(streams[key]);
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          (uri.hasPort && uri.port != 443) ||
          !(uri.host == 'twitcasting.tv' || uri.host.endsWith('.twitcasting.tv')) ||
          !RegExp('^/tc[.]livehls/v1/streams/$movieId/hls/[0-9]+[.][0-9]+/media[.]m3u8\$').hasMatch(uri.path)) {
        throw const TwitcastingException(TwitcastingFailure.schema);
      }
      qualities.add(
        _LegacyQuality(
          id: key,
          quality: 'HLS $key',
          sort: 3 - qualities.length,
          data: List<String>.unmodifiable([url]),
        ),
      );
    }
    if (qualities.isEmpty) throw const TwitcastingException(TwitcastingFailure.schema);
    room.data = List<_LegacyQuality>.unmodifiable(qualities);
    return room;
  }
}

class TwitcastingSite {
  TwitcastingSite({required TwitcastingApi api}) : _api = api;
  final TwitcastingApi _api;
  String get id => 'twitcasting';
  String get name => 'TwitCasting';

  Future<List<_LegacyCategory>> getCategores(int page, int pageSize) async =>
      page == 1 ? [_LegacyCategory(id: id, name: name, children: await _api.categories())] : [];

  Future<List<_LegacyRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) =>
      _api.directory(page: page, pageSize: pageSize);

  Future<List<_LegacyRoom>> getCategoryRooms(_LegacyArea category, {int page = 1, int pageSize = 30}) {
    if (category.platform != id ||
        category.areaType != 'directory' ||
        category.areaId == null ||
        category.areaId!.isEmpty) {
      throw const TwitcastingException(TwitcastingFailure.schema);
    }
    return _api.directory(page: page, pageSize: pageSize, category: category.areaId!);
  }

  Future<List<_LegacyRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      _api.searchLives(keyword, page: page, pageSize: pageSize);

  Future<_LegacyRoom> getRoomDetail({required String roomId, required String platform}) {
    if (platform != id) throw const TwitcastingException(TwitcastingFailure.schema);
    return _api.detail(roomId);
  }

  Future<_LegacyRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      getRoomDetail(roomId: roomId, platform: platform);

  Future<List<_LegacyQuality>> getPlayQualites({required _LegacyRoom detail}) async {
    if (detail.platform != id) throw const TwitcastingException(TwitcastingFailure.schema);
    if (detail.isExplicitlyOfflineNow) return [];
    if (detail.data is! List<_LegacyQuality>) throw const TwitcastingException(TwitcastingFailure.schema);
    return List.unmodifiable(detail.data as List<_LegacyQuality>);
  }

  Future<List<String>> getPlayUrls({required _LegacyRoom detail, required _LegacyQuality quality}) async {
    for (final current in await getPlayQualites(detail: detail)) {
      if (current.selectionId == quality.selectionId) return List.unmodifiable(current.data as List<String>);
    }
    throw const TwitcastingException(TwitcastingFailure.qualityUnavailable);
  }
}
