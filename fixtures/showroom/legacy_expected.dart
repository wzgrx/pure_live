// Writes expected.json for the SHOWROOM samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.19-showroom.md, "样本与 v3 的冻结输出").
//
// The archive has no SHOWROOM expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below is 3.x's
// ShowroomApi, ShowroomSite and ShowroomLink, copied from
// legacy/lib/core/site/showroom/ (archive/v4). 3.x already injected its
// transport (`ShowroomRequest`), so only that function is replaced: it
// answers from the samples by host, path and query, with the empty body 3.x
// read for any status other than 200, and records a request without a
// sample (which 3.x's `_get` reports as a transport failure) under
// `unmatched`. One answer is not recorded: `live/live_info?room_id=1`, which
// 3.x asks for together with S03-profile-notfound; the harness answers it
// with the 404 the site gives every unknown room (spec/sites/showroom.md §1:
// `room/profile`, `room/status` and `live/live_info` all answer 404), and
// says so in the output.
//
// `i18n` is replaced by the Chinese text of the keys used
// (`showroom_quality_*`, 3.x's zh.json); the danmaku getter is left out.
// Dio's CancelToken, 3.x's LiveRoom, LiveArea, LiveCategory, LivePlayQuality,
// LiveDirectoryPage and LivePlayUrlResolution are reduced to the parts these
// classes use (constructor defaults, the mutable fields, isLiveNow,
// isExplicitlyOfflineNow, selectionId, toJson with 3.x's
// HttpHeaderPolicy.normalize). The streamed body reader (`_defaultRequest`,
// `readBody`) is left out: it only ran on the network path. The output
// format is the legacy harness's (`roomProjection`, `errorProjection`,
// `{generator, value}`); every entry point also records its requests.
//
// Run from the repository root: dart run fixtures/showroom/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/showroom';

/// Keywords run against the S01 snapshot: a room id, a room key in another
/// case, an all-digit room key, a name, a telop, a live's genre name, a word
/// in many names (paging) and none.
const _keywords = ['577362', '0C1C310117354', '7779344804', 'king', '雑談', 'バーチャル', 'room', 'zxqvnoresultfixture'];

/// Links for 3.x's `ShowroomLink.parse` (no requests).
const _links = [
  'https://www.showroom-live.com/r/0c1c310117354',
  'https://www.showroom-live.com/r/0c1c310117354?t=1790532886',
  'https://www.showroom-live.com/48_Seina_Fukuoka',
  'https://showroom-live.com/r/48_Seina_Fukuoka/',
  'http://www.showroom-live.com/r/7779344804',
  'https://www.showroom-live.com/room/profile?room_id=61576',
  'https://www.showroom-live.com/room/profile?room_id=0061576',
  'https://www.showroom-live.com/room/profile',
  'https://www.showroom-live.com/event/some_event',
  'https://www.showroom-live.com/ranking',
  'https://www.showroom-live.com/onlive',
  'https://www.showroom-live.com/r',
  'https://www.showroom-live.com/campaign/x',
  'https://www.showroom-live.com/r/a/b',
  'https://www.showroom-live.com/',
  'https://user@www.showroom-live.com/r/abc',
  'https://evilshowroom-live.com/r/abc',
  'https://www.showroom-live.com/r/%E3%81%82',
  'ftp://www.showroom-live.com/r/abc',
  'https://m.showroom-live.com/r/abc',
];

void main() async {
  await _snapshot();
  await _room(
    'S03-profile-live',
    samples: ['S02-status-key', 'S03-profile-live', 'S04-live-info-live', 'S05-streaming-live'],
    references: ['577362', '0c1c310117354'],
  );
  await _room(
    'S03-profile-offline',
    samples: ['S03-profile-offline', 'S04-live-info-offline', 'S05-streaming-offline'],
    references: ['61576'],
  );
  await _room('S03-profile-notfound', samples: ['S03-profile-notfound'], references: ['1'], unknownRoomInfo: true);
  await _room('S02-status-notfound', samples: ['S02-status-notfound'], references: ['zxqvnoroomfixture']);
  await _statusKey();
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final List<String> _requests = [];
final List<String> _unmatched = [];
bool _unknownRoomInfo = false;

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _replay(List<String> samples, {bool unknownRoomInfo = false}) {
  _samples = [for (final sample in samples) _meta(sample)];
  _unknownRoomInfo = unknownRoomInfo;
  _requests.clear();
  _unmatched.clear();
}

bool _sameQuery(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

/// 3.x's `ShowroomRequest` over the samples: 3.x read no body for a status
/// other than 200.
Future<({int status, String body})> _fixtureRequest(Uri uri, CancelToken? cancel) async {
  _requests.add(uri.toString());
  for (final meta in _samples) {
    final recorded = Uri.parse((meta['request'] as Map)['url'] as String);
    if (recorded.host == uri.host &&
        recorded.path == uri.path &&
        _sameQuery(recorded.queryParameters, uri.queryParameters)) {
      final status = (meta['response'] as Map)['status'] as int;
      if (status != 200) return (status: status, body: '');
      return (status: 200, body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync());
    }
  }
  if (_unknownRoomInfo && uri.path == '/api/live/live_info' && uri.queryParameters['room_id'] == '1') {
    return (status: 404, body: '');
  }
  _unmatched.add(uri.toString());
  throw StateError('No recorded sample for GET $uri');
}

ShowroomSite _site() => ShowroomSite(api: ShowroomApi(request: _fixtureRequest));

void _write(String sample, String generator, Object? value) {
  final file = File('$_root/$sample/expected.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'generator': generator, 'value': jsonDecode(jsonEncode(value))})}\n',
  );
  stdout.writeln('wrote $sample');
}

Map<String, dynamic> _errorProjection(Object error) => {
  'throws': switch (error) {
    TypeError() => 'TypeError',
    FormatException() => 'FormatException',
    StateError() => 'StateError',
    _ => error.runtimeType.toString(),
  },
  'message': error.toString(),
};

Future<Object?> _outcome<T>(Future<T> Function() body, Object? Function(T value) project) async {
  try {
    return project(await body());
  } on Object catch (error) {
    return _errorProjection(error);
  }
}

/// [body]'s outcome and the requests it sent.
Future<Map<String, Object?>> _traced<T>(Future<T> Function() body, Object? Function(T value) project) async {
  _requests.clear();
  _unmatched.clear();
  final result = await _outcome(body, project);
  return {
    'result': result,
    'requests': [..._requests],
    if (_unmatched.isNotEmpty) 'unmatched': [..._unmatched],
  };
}

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere(
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

Object? _page(LiveDirectoryPage page) => {'rooms': _rooms(page.rooms), 'page': page.page, 'hasMore': page.hasMore};

Object? _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
];

// Samples ---------------------------------------------------------------------

LiveArea _genre(Object id, String name) =>
    LiveArea(platform: 'showroom', areaType: 'genre', typeName: 'SHOWROOM', areaId: '$id', areaName: name);

/// `live/onlives`: categories, the native directory pages (recommendations
/// and every genre), 3.x's slices and the keyword search over the snapshot.
/// The site caches a snapshot for 30 s unless a cancel token is passed (the
/// directory controller and the search page always pass one), so every call
/// here gets a new ShowroomSite and records its own request.
Future<void> _snapshot() async {
  _replay(['S01-onlives']);
  final value = <String, Object?>{
    'getCategores': await _traced(
      () => _site().getCategores(1, 30),
      (categories) => [
        for (final category in categories)
          {
            'id': category.id,
            'name': category.name,
            'children': [for (final area in category.children) area.toJson()],
          },
      ],
    ),
    'getCategores(page: 2)': await _traced(() => _site().getCategores(2, 30), (categories) => categories.length),
  };
  final genres = (await _site().getCategores(1, 30)).single.children;
  final directory = <String, Object?>{};
  for (final page in [1, 2, 3, 4]) {
    directory['recommend:$page'] = await _traced(
      () => _site().getDirectoryPage(page: page, cancel: CancelToken()),
      _page,
    );
  }
  for (final genre in genres) {
    for (final page in [1, 2]) {
      directory['${genre.areaId}:$page'] = await _traced(
        () => _site().getDirectoryPage(page: page, category: genre, cancel: CancelToken()),
        _page,
      );
    }
  }
  directory['99999:1'] = await _traced(
    () => _site().getDirectoryPage(category: _genre(99999, 'Gone'), cancel: CancelToken()),
    _page,
  );
  directory['otherPlatform:1'] = await _traced(
    () => _site().getDirectoryPage(
      category: LiveArea(platform: 'bilibili', areaType: 'genre', areaId: '0', areaName: 'x'),
      cancel: CancelToken(),
    ),
    _page,
  );
  directory['recommend:0'] = await _traced(() => _site().getDirectoryPage(page: 0, cancel: CancelToken()), _page);
  value['getDirectoryPage'] = directory;
  value['getRecommendRooms'] = {
    for (final (page, size) in [(1, 30), (2, 30), (3, 30), (1, 20), (4, 20), (1, 100), (1, 101), (0, 30)])
      'page $page size $size': await _traced(() => _site().getRecommendRooms(page: page, pageSize: size), _rooms),
  };
  value['getCategoryRooms'] = {
    for (final (id, name, page) in [(112, 'Music', 1), (112, 'Music', 2), (758, 'Newcomer', 1), (99999, 'Gone', 1)])
      '$id page $page': await _traced(() => _site().getCategoryRooms(_genre(id, name), page: page), _rooms),
  };
  final search = <String, Object?>{};
  for (final keyword in _keywords) {
    search['$keyword page 1'] = await _traced(
      () => _site().searchRoomsCancellable(keyword, page: 1, pageSize: 20, cancel: CancelToken()),
      _rooms,
    );
  }
  search['room page 2'] = await _traced(
    () => _site().searchRoomsCancellable('room', page: 2, pageSize: 20, cancel: CancelToken()),
    _rooms,
  );
  search['blank'] = await _traced(() => _site().searchRooms('  ', page: 1, pageSize: 20), _rooms);
  search['link'] = await _traced(
    () => _site().searchRooms('https://www.showroom-live.com/r/0c1c310117354', page: 1, pageSize: 20),
    _rooms,
  );
  value['searchRooms (pageSize 20)'] = search;
  // The 30 s cache: two calls on one site without a cancel token, then one
  // with a token.
  final cached = _site();
  value['cache'] = await _traced(() async {
    await cached.getCategores(1, 30);
    await cached.getRecommendRooms();
    await cached.searchRooms('king');
    await cached.getDirectoryPage(cancel: CancelToken());
    return true;
  }, (value) => value);
  _write(
    'S01-onlives',
    'ShowroomSite.getCategores + getDirectoryPage + getRecommendRooms + getCategoryRooms + searchRooms',
    value,
  );
}

/// A room by each of [references]: room entry, refresh, recording, live
/// status, qualities with their URLs and recovery, with every request.
Future<void> _room(
  String sample, {
  required List<String> samples,
  required List<String> references,
  bool unknownRoomInfo = false,
}) async {
  _replay(samples, unknownRoomInfo: unknownRoomInfo);
  final value = <String, Object?>{};
  if (unknownRoomInfo) value['synthetic'] = 'live/live_info?room_id=1 answered 404 (not recorded; spec §1)';
  for (final reference in references) {
    final site = _site();
    final entry = <String, Object?>{
      'getRoomDetail': await _traced(
        () => site.getRoomDetail(roomId: reference, platform: 'showroom'),
        _roomProjection,
      ),
      'getRoomDetailForRefresh': await _traced(
        () => site.getRoomDetailForRefresh(roomId: reference, platform: 'showroom'),
        _roomProjection,
      ),
      'getRoomDetailForRecording': await _traced(
        () => site.getRoomDetailForRecording(roomId: reference, platform: 'showroom'),
        _roomProjection,
      ),
      'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: reference, platform: 'showroom'), (live) => live),
    };
    LiveRoom? detail;
    try {
      detail = await site.getRoomDetail(roomId: reference, platform: 'showroom');
    } on Object {
      detail = null;
    }
    if (detail != null) {
      final room = detail;
      entry['getPlayQualites'] = await _traced(() => site.getPlayQualites(detail: room), _qualities);
      List<LivePlayQuality> qualities;
      try {
        qualities = await site.getPlayQualites(detail: room);
      } on Object {
        qualities = const [];
      }
      entry['getPlayUrls'] = {
        for (final quality in qualities)
          '${quality.id}': await _traced(() => site.getPlayUrls(detail: room, quality: quality), (urls) => urls),
      };
      final probe = qualities.isNotEmpty
          ? qualities.first
          : LivePlayQuality(quality: '原画', id: 'hls:2:1000', sort: 1000, data: const <String>[]);
      entry['resolvePlayUrlsForRecoveryRaw(${probe.id})'] = await _traced(
        () => site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: probe),
        (resolution) => {'urls': resolution.urls, 'appliedQualityData': resolution.appliedQualityData},
      );
    }
    value[reference] = entry;
  }
  _write(
    sample,
    'ShowroomSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
    'getPlayQualites + getPlayUrls + resolvePlayUrlsForRecoveryRaw (with ${samples.join(', ')})',
    value,
  );
}

/// `room/status`: the key lookup, and 3.x's link rules (no requests).
Future<void> _statusKey() async {
  _replay(['S02-status-key']);
  final api = ShowroomApi(request: _fixtureRequest);
  _write('S02-status-key', 'ShowroomApi.resolveRoomId + ShowroomLink.parse + ShowroomLink.roomUrl', {
    'resolveRoomId': {
      for (final reference in ['0c1c310117354', '577362', ' 577362 ', 'a b', '../x'])
        reference: await _traced(() => api.resolveRoomId(reference), (id) => id),
    },
    'ShowroomLink.parse': {for (final link in _links) link: ShowroomLink.parse(link)},
    'ShowroomLink.roomUrl': {
      for (final id in ['577362', '0c1c310117354'])
        id: () {
          try {
            return ShowroomLink.roomUrl(id);
          } on Object catch (error) {
            return _errorProjection(error);
          }
        }(),
    },
  });
}

// 3.x models (the parts the SHOWROOM classes use) ----------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

class CancelToken {
  bool isCancelled = false;
}

String i18n(String key) => const {
  'showroom_quality_auto': '自动',
  'showroom_quality_original': '原画',
  'showroom_quality_medium': '中画质',
  'showroom_quality_low': '低画质',
}[key]!;

class HttpHeaderPolicy {
  static final RegExp _validName = RegExp(r'^[a-z0-9-]+$');

  static Map<String, String> normalize(Map<dynamic, dynamic>? source) {
    if (source == null || source.isEmpty) return const <String, String>{};
    final result = <String, String>{};
    for (final entry in source.entries) {
      if (entry.key is! String || entry.value is! String) continue;
      final name = canonicalName(entry.key as String);
      final value = (entry.value as String).replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ').trim();
      if (name != null && value.isNotEmpty) result[name] = value;
    }
    if (result.isEmpty) return const <String, String>{};
    final sorted = result.entries.toList()..sort((left, right) => left.key.compareTo(right.key));
    return Map<String, String>.unmodifiable({for (final entry in sorted) entry.key: entry.value});
  }

  static String? canonicalName(String raw) {
    var name = raw.trim().toLowerCase();
    if (name.startsWith('!')) name = name.substring(1);
    name = switch (name) {
      'http-user-agent' => 'user-agent',
      'http-referrer' || 'http-referer' || 'referrer' => 'referer',
      'cookies' => 'cookie',
      _ => name,
    };
    return name.isNotEmpty && _validName.hasMatch(name) ? name : null;
  }
}

class LiveArea {
  LiveArea({this.platform, this.areaType, this.typeName, this.areaId, this.areaName, this.areaPic, this.shortName});

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

class LiveCategory {
  LiveCategory({required this.id, required this.name, required this.children});

  final String name;
  final String id;
  final List<LiveArea> children;
}

class LivePlayQuality {
  LivePlayQuality({required this.quality, this.data, this.id, this.sort = 0});

  final String quality;
  final dynamic data;
  final Object? id;
  final int sort;

  Object get selectionId => id ?? quality;
}

class LivePlayUrlResolution {
  const LivePlayUrlResolution({required this.urls, this.appliedQualityData});

  final List<String> urls;
  final Object? appliedQualityData;
}

class LiveDirectoryPage {
  LiveDirectoryPage({required Iterable<LiveRoom> rooms, required this.page, required this.hasMore})
    : rooms = List.unmodifiable(rooms);
  final List<LiveRoom> rooms;
  final int page;
  final bool hasMore;
}

class LiveRoom {
  LiveRoom({
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
    this.httpHeaders = const <String, String>{},
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
  Map<String, String> httpHeaders;

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

  bool get isExplicitlyOfflineNow =>
      effectiveLiveStatus == LiveStatus.offline || effectiveLiveStatus == LiveStatus.banned;

  AudienceMetricType get effectiveAudienceMetricType {
    if (audienceMetricType != null && audienceMetricType != AudienceMetricType.unknown) return audienceMetricType!;
    return AudienceMetricType.unknown;
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
    'httpHeaders': HttpHeaderPolicy.normalize(httpHeaders),
  };
}

// 3.x's SHOWROOM adapter (legacy/lib/core/site/showroom/) --------------------
//
// Unchanged apart from the model names above and the transport: no Dio, so
// `CancelToken` is the stub above, the `DioException` check in `_get` is
// gone (the stub never throws one), and `_defaultRequest` / `readBody` are
// left out.

enum ShowroomFailure {
  transport,
  access,
  rateLimited,
  service,
  missing,
  schema,
  cancelled,
  identity,
  notLive,
  mediaUnavailable,
}

class ShowroomException implements Exception {
  const ShowroomException(this.kind);

  final ShowroomFailure kind;

  @override
  String toString() => 'Showroom ${kind.name}';
}

typedef ShowroomRequest = Future<({int status, String body})> Function(Uri uri, CancelToken? cancel);

class ShowroomStream {
  const ShowroomStream({
    required this.id,
    required this.type,
    required this.label,
    required this.quality,
    required this.url,
    required this.isDefault,
  });

  final int id;
  final String type;
  final String label;
  final int quality;
  final String url;
  final bool isDefault;
}

class ShowroomLive {
  ShowroomLive({
    required this.roomId,
    required this.roomUrlKey,
    required this.name,
    required this.cover,
    required this.genreId,
    required this.genreName,
    required this.followers,
    required this.totalViewers,
    required this.telop,
    required Iterable<ShowroomStream> streams,
  }) : streams = List.unmodifiable(streams);

  final int roomId;
  final String roomUrlKey;
  final String name;
  final String cover;
  final int genreId;
  final String genreName;
  final int? followers;
  final int? totalViewers;
  final String telop;
  final List<ShowroomStream> streams;
}

class ShowroomGenre {
  ShowroomGenre({required this.id, required this.name, required Iterable<ShowroomLive> lives})
    : lives = List.unmodifiable(lives);

  final int id;
  final String name;
  final List<ShowroomLive> lives;
}

class ShowroomCatalog {
  ShowroomCatalog(Iterable<ShowroomGenre> genres) : genres = List.unmodifiable(genres);

  final List<ShowroomGenre> genres;

  Iterable<ShowroomLive> get uniqueLives sync* {
    final seen = <int>{};
    for (final genre in genres) {
      for (final live in genre.lives) {
        if (seen.add(live.roomId)) yield live;
      }
    }
  }
}

class ShowroomProfile {
  const ShowroomProfile({
    required this.roomId,
    required this.roomUrlKey,
    required this.name,
    required this.cover,
    required this.genreId,
    required this.genreName,
    required this.followers,
    required this.totalViewers,
    required this.description,
    required this.isLive,
  });

  final int roomId;
  final String roomUrlKey;
  final String name;
  final String cover;
  final int genreId;
  final String genreName;
  final int? followers;
  final int? totalViewers;
  final String description;
  final bool isLive;

  ShowroomProfile withLiveStatus(bool value) => ShowroomProfile(
    roomId: roomId,
    roomUrlKey: roomUrlKey,
    name: name,
    cover: cover,
    genreId: genreId,
    genreName: genreName,
    followers: followers,
    totalViewers: totalViewers,
    description: description,
    isLive: value,
  );
}

class ShowroomRoom {
  ShowroomRoom(this.profile, Iterable<ShowroomStream> streams) : streams = List.unmodifiable(streams);

  final ShowroomProfile profile;
  final List<ShowroomStream> streams;
}

class ShowroomApi {
  ShowroomApi({required ShowroomRequest request}) : _request = request;

  static const origin = 'https://www.showroom-live.com';
  static const responseLimit = 3 * 1024 * 1024;
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  static const headers = {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Referer': '$origin/',
  };
  static const mediaHeaders = {'User-Agent': userAgent, 'Referer': '$origin/'};

  final ShowroomRequest _request;

  Future<Object?> _get(String path, Map<String, String> query, CancelToken? cancel) async {
    if (cancel?.isCancelled == true) throw const ShowroomException(ShowroomFailure.cancelled);
    late final ({int status, String body}) response;
    try {
      response = await _request(Uri.parse('$origin$path').replace(queryParameters: query), cancel);
    } catch (error) {
      if (cancel?.isCancelled == true) {
        throw const ShowroomException(ShowroomFailure.cancelled);
      }
      if (error is ShowroomException) rethrow;
      throw const ShowroomException(ShowroomFailure.transport);
    }
    if (cancel?.isCancelled == true) throw const ShowroomException(ShowroomFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      401 || 403 => ShowroomFailure.access,
      404 => ShowroomFailure.missing,
      429 => ShowroomFailure.rateLimited,
      >= 500 => ShowroomFailure.service,
      _ => ShowroomFailure.transport,
    };
    if (failure != null) throw ShowroomException(failure);
    if (response.body.length > responseLimit) throw const ShowroomException(ShowroomFailure.schema);
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const ShowroomException(ShowroomFailure.schema);
    }
  }

  Future<ShowroomCatalog> catalog({CancelToken? cancel}) async {
    final root = _object(await _get('/api/live/onlives', const {}, cancel));
    final groups = _list(root['onlives'], max: 128);
    final genres = <ShowroomGenre>[];
    final seen = <int>{};
    for (final rawGroup in groups) {
      final group = _object(rawGroup);
      final id = _nonNegativeInt(group['genre_id']);
      if (!seen.add(id)) continue;
      final name = _text(group['genre_name']);
      final lives = _list(group['lives'], max: 5000)
          .map(_object)
          // A genre with nobody live carries a message cell (`cell_type: 7`,
          // no room) instead of an empty list. Skip such non-room cells; real
          // live rows keep their strict validation.
          .where((row) => row['room_id'] != null || row['cell_type'] == null)
          .map(_live)
          .toList(growable: false);
      genres.add(ShowroomGenre(id: id, name: name, lives: lives));
    }
    if (genres.isEmpty) throw const ShowroomException(ShowroomFailure.schema);
    return ShowroomCatalog(genres);
  }

  Future<int> resolveRoomId(String reference, {CancelToken? cancel}) async {
    final normalized = reference.trim();
    final numeric = int.tryParse(normalized);
    if (numeric != null && numeric > 0) return numeric;
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(normalized)) {
      throw const ShowroomException(ShowroomFailure.identity);
    }
    final data = _object(await _get('/api/room/status', {'room_url_key': normalized}, cancel));
    return _positiveInt(data['room_id']);
  }

  Future<ShowroomProfile> profile(int roomId, {CancelToken? cancel}) async {
    if (roomId <= 0) throw const ShowroomException(ShowroomFailure.identity);
    final data = _object(await _get('/api/room/profile', {'room_id': '$roomId'}, cancel));
    final actualId = _positiveInt(data['room_id']);
    if (actualId != roomId) throw const ShowroomException(ShowroomFailure.identity);
    return ShowroomProfile(
      roomId: actualId,
      roomUrlKey: _slug(data['room_url_key']),
      name: _text(data['main_name'] ?? data['room_name']),
      cover: _image(data['image_square']),
      genreId: _nonNegativeInt(data['genre_id']),
      genreName: _optionalText(data['genre_name']),
      followers: _optionalNonNegativeInt(data['follower_num']),
      // SHOWROOM calls this view_num. It is session traffic, not a proven
      // concurrent audience count, so the site exposes it as total viewers.
      totalViewers: _optionalNonNegativeInt(data['view_num']),
      description: _optionalText(data['description']),
      isLive: _bool(data['is_onlive']),
    );
  }

  Future<bool> liveStatus(int roomId, {CancelToken? cancel}) async {
    if (roomId <= 0) throw const ShowroomException(ShowroomFailure.identity);
    final data = _object(await _get('/api/live/live_info', {'room_id': '$roomId'}, cancel));
    final actualId = _positiveInt(data['room_id']);
    if (actualId != roomId) throw const ShowroomException(ShowroomFailure.identity);
    final status = _nonNegativeInt(data['live_status']);
    if (status > 2) throw const ShowroomException(ShowroomFailure.schema);
    return status == 2;
  }

  Future<List<ShowroomStream>> streams(int roomId, {CancelToken? cancel}) async {
    if (roomId <= 0) throw const ShowroomException(ShowroomFailure.identity);
    final data = _object(await _get('/api/live/streaming_url', {'room_id': '$roomId', 'abr_available': '1'}, cancel));
    final streams = <ShowroomStream>[];
    final seen = <String>{};
    for (final raw in _list(data['streaming_url_list'], max: 64)) {
      final row = _object(raw);
      final type = _optionalText(row['type']);
      if (type != 'hls' && type != 'hls_all') continue;
      final url = mediaUrl(row['url']);
      if (!seen.add(url)) continue;
      streams.add(
        ShowroomStream(
          id: _nonNegativeInt(row['id']),
          type: type,
          label: _text(row['label']),
          quality: _nonNegativeInt(row['quality']),
          url: url,
          isDefault: _bool(row['is_default']),
        ),
      );
    }
    return List.unmodifiable(streams);
  }

  Future<ShowroomRoom> room(String reference, {required bool playback, CancelToken? cancel}) async {
    final roomId = await resolveRoomId(reference, cancel: cancel);
    final results = await Future.wait<Object>([profile(roomId, cancel: cancel), liveStatus(roomId, cancel: cancel)]);
    final profileResult = (results[0] as ShowroomProfile).withLiveStatus(results[1] as bool);
    if (!playback || !profileResult.isLive) return ShowroomRoom(profileResult, const []);
    final media = await streams(roomId, cancel: cancel);
    if (media.isEmpty) throw const ShowroomException(ShowroomFailure.mediaUnavailable);
    return ShowroomRoom(profileResult, media);
  }

  static ShowroomLive _live(Map<String, dynamic> data) {
    final roomId = _positiveInt(data['room_id']);
    final streams = <ShowroomStream>[];
    final seen = <String>{};
    for (final raw in _list(data['streaming_url_list'], max: 64)) {
      final row = _object(raw);
      final type = _optionalText(row['type']);
      if (type != 'hls' && type != 'hls_all') continue;
      final url = mediaUrl(row['url']);
      if (!seen.add(url)) continue;
      streams.add(
        ShowroomStream(
          id: _nonNegativeInt(row['id']),
          type: type,
          label: _text(row['label']),
          quality: _nonNegativeInt(row['quality']),
          url: url,
          isDefault: _bool(row['is_default']),
        ),
      );
    }
    return ShowroomLive(
      roomId: roomId,
      roomUrlKey: _slug(data['room_url_key']),
      name: _text(data['main_name']),
      cover: _image(data['image_square'] ?? data['image']),
      genreId: _nonNegativeInt(data['genre_id']),
      genreName: _optionalText(data['genre_name']),
      followers: _optionalNonNegativeInt(data['follower_num']),
      totalViewers: _optionalNonNegativeInt(data['view_num']),
      telop: _optionalText(data['telop']),
      streams: streams,
    );
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const ShowroomException(ShowroomFailure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<dynamic> _list(Object? value, {required int max}) {
    if (value is! List || value.length > max) throw const ShowroomException(ShowroomFailure.schema);
    return value;
  }

  static int _positiveInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed <= 0) throw const ShowroomException(ShowroomFailure.schema);
    return parsed;
  }

  static int _nonNegativeInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 0) throw const ShowroomException(ShowroomFailure.schema);
    return parsed;
  }

  static int? _optionalNonNegativeInt(Object? value) {
    if (value == null || value == '') return null;
    return _nonNegativeInt(value);
  }

  static bool _bool(Object? value) {
    if (value is! bool) throw const ShowroomException(ShowroomFailure.schema);
    return value;
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 8192) {
      throw const ShowroomException(ShowroomFailure.schema);
    }
    return value.trim();
  }

  static String _optionalText(Object? value) {
    if (value == null) return '';
    if (value is! String || value.length > 131072) throw const ShowroomException(ShowroomFailure.schema);
    return value.trim();
  }

  static String _slug(Object? value) {
    final result = _text(value);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(result)) {
      throw const ShowroomException(ShowroomFailure.identity);
    }
    return result;
  }

  static bool _trustedHost(String host) =>
      host == 'showroom-live.com' ||
      host.endsWith('.showroom-live.com') ||
      host == 'showroom-txlive.com' ||
      host.endsWith('.showroom-txlive.com');

  static String _image(Object? value) {
    if (value is! String || value.length > 8192) return '';
    final uri = Uri.tryParse(value);
    return uri != null && uri.scheme == 'https' && uri.userInfo.isEmpty && _trustedHost(uri.host.toLowerCase())
        ? value
        : '';
  }

  static String mediaUrl(Object? value) {
    if (value is! String || value.length > 8192 || value.contains(RegExp(r'[\s\x00-\x1f]'))) {
      throw const ShowroomException(ShowroomFailure.schema);
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        !_trustedHost(uri.host.toLowerCase())) {
      throw const ShowroomException(ShowroomFailure.schema);
    }
    return value;
  }
}

class _ShowroomPlayback {
  _ShowroomPlayback(this.roomId, Iterable<LivePlayQuality> qualities) : qualities = List.unmodifiable(qualities);

  final String roomId;
  final List<LivePlayQuality> qualities;
}

class ShowroomSite {
  ShowroomSite({ShowroomApi? api}) : _api = api!;

  final ShowroomApi _api;
  Future<ShowroomCatalog>? _catalogRequest;
  DateTime? _catalogAt;

  String get id => 'showroom';

  String get name => 'SHOWROOM';

  String get directoryNoticeKey => 'showroom_directory_scope';

  Future<ShowroomCatalog> _catalog({CancelToken? cancel}) {
    if (cancel != null) return _api.catalog(cancel: cancel);
    final now = DateTime.now();
    final cached = _catalogRequest;
    if (cached != null && _catalogAt != null && now.difference(_catalogAt!) < const Duration(seconds: 30)) {
      return cached;
    }
    late final Future<ShowroomCatalog> request;
    request = _api
        .catalog()
        .then((value) {
          _catalogAt = DateTime.now();
          return value;
        })
        .catchError((Object error) {
          if (identical(_catalogRequest, request)) {
            _catalogRequest = null;
            _catalogAt = null;
          }
          throw error;
        });
    _catalogRequest = request;
    return request;
  }

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    if (page != 1 || pageSize <= 0) return [];
    final catalog = await _catalog();
    return [
      LiveCategory(
        id: id,
        name: name,
        children: catalog.genres
            .map(
              (genre) => LiveArea(
                platform: id,
                areaType: 'genre',
                typeName: name,
                areaId: '${genre.id}',
                areaName: genre.name,
              ),
            )
            .toList(growable: false),
      ),
    ];
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) throw const ShowroomException(ShowroomFailure.schema);
    final catalog = await _catalog(cancel: cancel);
    final rooms = category == null ? _popular(catalog) : _category(catalog, category);
    const pageSize = 30;
    final start = (page - 1) * pageSize;
    if (start >= rooms.length) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final end = (start + pageSize).clamp(0, rooms.length);
    return LiveDirectoryPage(rooms: rooms.sublist(start, end).map(_card), page: page, hasMore: end < rooms.length);
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    final rooms = _popular(await _catalog());
    return _page(rooms, page, pageSize).map(_card).toList(growable: false);
  }

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final rooms = _category(await _catalog(), category);
    return _page(rooms, page, pageSize).map(_card).toList(growable: false);
  }

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty || page < 1 || pageSize < 1) return [];
    final catalog = await _catalog(cancel: cancel);
    final matches = catalog.uniqueLives
        .where((room) {
          return '${room.roomId}' == query ||
              room.roomUrlKey.toLowerCase() == query ||
              room.name.toLowerCase().contains(query) ||
              room.telop.toLowerCase().contains(query) ||
              room.genreName.toLowerCase().contains(query);
        })
        .toList(growable: false);
    return _page(matches, page, pageSize).map(_card).toList(growable: false);
  }

  static List<ShowroomLive> _popular(ShowroomCatalog catalog) {
    for (final genre in catalog.genres) {
      if (genre.id == 0) return genre.lives;
    }
    return catalog.uniqueLives.toList(growable: false);
  }

  List<ShowroomLive> _category(ShowroomCatalog catalog, LiveArea category) {
    if (category.platform != id || category.areaType != 'genre') {
      throw const ShowroomException(ShowroomFailure.identity);
    }
    final genreId = int.tryParse(category.areaId ?? '');
    if (genreId == null || genreId < 0) throw const ShowroomException(ShowroomFailure.identity);
    for (final genre in catalog.genres) {
      if (genre.id == genreId) return genre.lives;
    }
    throw const ShowroomException(ShowroomFailure.missing);
  }

  static List<T> _page<T>(List<T> values, int page, int pageSize) {
    if (page < 1 || pageSize < 1 || pageSize > 100) return [];
    final start = (page - 1) * pageSize;
    if (start >= values.length) return [];
    return values.sublist(start, (start + pageSize).clamp(0, values.length));
  }

  static LiveRoom _card(ShowroomLive live) {
    final audience = live.totalViewers?.toString();
    return LiveRoom(
      platform: 'showroom',
      roomId: '${live.roomId}',
      link: 'https://www.showroom-live.com/r/${live.roomUrlKey}',
      nick: live.name,
      title: live.telop.isEmpty ? live.name : live.telop,
      avatar: live.cover,
      cover: live.cover,
      area: live.genreName,
      followers: live.followers?.toString(),
      watching: audience,
      totalViewers: audience,
      audienceMetricType: AudienceMetricType.totalViewers,
      liveStatus: LiveStatus.live,
      httpHeaders: ShowroomApi.mediaHeaders,
    );
  }

  LiveRoom _detailCard(ShowroomRoom room) {
    final profile = room.profile;
    final audience = profile.totalViewers?.toString();
    final qualities = room.streams.map(_quality).toList(growable: false)
      ..sort((left, right) {
        final rank = right.sort.compareTo(left.sort);
        return rank != 0 ? rank : left.selectionId.toString().compareTo(right.selectionId.toString());
      });
    return LiveRoom(
      platform: id,
      roomId: '${profile.roomId}',
      link: 'https://www.showroom-live.com/r/${profile.roomUrlKey}',
      nick: profile.name,
      title: profile.name,
      avatar: profile.cover,
      cover: profile.cover,
      area: profile.genreName,
      followers: profile.followers?.toString(),
      watching: audience,
      totalViewers: audience,
      audienceMetricType: AudienceMetricType.totalViewers,
      introduction: profile.description,
      liveStatus: profile.isLive ? LiveStatus.live : LiveStatus.offline,
      data: profile.isLive && qualities.isNotEmpty ? _ShowroomPlayback('${profile.roomId}', qualities) : null,
      httpHeaders: ShowroomApi.mediaHeaders,
    );
  }

  static LivePlayQuality _quality(ShowroomStream stream) {
    final label = switch ((stream.type, stream.quality)) {
      ('hls_all', _) => i18n('showroom_quality_auto'),
      (_, >= 1000) => i18n('showroom_quality_original'),
      (_, >= 200) => i18n('showroom_quality_medium'),
      (_, _) => i18n('showroom_quality_low'),
    };
    return LivePlayQuality(
      id: '${stream.type}:${stream.id}:${stream.quality}',
      quality: label,
      sort: stream.type == 'hls_all' ? 2000 : stream.quality,
      data: <String>[stream.url],
    );
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool playback}) async {
    if (platform.trim().toLowerCase() != id) throw const ShowroomException(ShowroomFailure.identity);
    return _detailCard(await _api.room(roomId, playback: playback));
  }

  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) =>
      _detail(roomId, platform, playback: true);

  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      _detail(roomId, platform, playback: true);

  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      _detail(roomId, platform, playback: false);

  Future<bool> getLiveStatus({required String platform, required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId, platform: platform)).isLiveNow;

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.platform != id) throw const ShowroomException(ShowroomFailure.identity);
    if (detail.isExplicitlyOfflineNow) return [];
    final data = detail.data;
    if (data is! _ShowroomPlayback || data.roomId != detail.roomId || data.qualities.isEmpty) {
      throw const ShowroomException(ShowroomFailure.mediaUnavailable);
    }
    return data.qualities;
  }

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    for (final current in await getPlayQualites(detail: detail)) {
      if (current.selectionId == quality.selectionId) return List.unmodifiable(current.data as List<String>);
    }
    throw const ShowroomException(ShowroomFailure.mediaUnavailable);
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final fresh = await getRoomDetail(roomId: detail.roomId ?? '', platform: id);
    return LivePlayUrlResolution(
      urls: await getPlayUrls(detail: fresh, quality: quality),
      appliedQualityData: quality.selectionId,
    );
  }
}

class ShowroomLink {
  const ShowroomLink._();

  static const Set<String> _reserved = {
    'api',
    'room',
    'event',
    'ranking',
    'search',
    'login',
    'register',
    'mypage',
    'premium_live',
  };

  /// Returns either the durable numeric room ID or the public room_url_key.
  /// The adapter resolves room_url_key through the official status endpoint.
  static String? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        !_isHost(uri.host.toLowerCase())) {
      return null;
    }
    final segments = uri.pathSegments.where((value) => value.isNotEmpty).toList(growable: false);
    if (segments.length == 2 && segments[0] == 'room' && segments[1] == 'profile') {
      final roomId = uri.queryParameters['room_id']?.trim() ?? '';
      return RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(roomId) ? roomId : null;
    }
    if (segments.length == 2 && segments.first == 'r') return _slug(segments[1]);
    if (segments.length == 1) return _slug(segments.single);
    return null;
  }

  static String roomUrl(Object roomId) {
    final value = roomId.toString().trim();
    if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(value)) throw const FormatException('Invalid SHOWROOM room ID');
    return 'https://www.showroom-live.com/room/profile?room_id=$value';
  }

  static bool _isHost(String host) => host == 'showroom-live.com' || host.endsWith('.showroom-live.com');

  static String? _slug(String value) {
    final normalized = value.trim();
    if (_reserved.contains(normalized.toLowerCase()) || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }
}
