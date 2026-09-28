// Writes expected.json for the niconico samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.17-niconico.md, "样本与 v3 的冻结输出").
//
// The archive has no niconico expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below is 3.x's, copied
// from legacy/lib/core/site/niconico/ (niconico_watch.dart, niconico_api.dart,
// niconico_directory.dart, niconico_site.dart, niconico_stream.dart) and
// legacy/lib/core/common/hls_session_cookies.dart (archive/v4) with only the
// transport replaced: `_replay` answers a listing from the sample recorded
// for its path and query, and any watch page from the watch sample loaded
// for the run (the samples were recorded as `watch/user/<id>` and
// `watch/ch<id>`, which serve the same page as the program id 3.x asks
// for); like 3.x's `_defaultRequest`, a non-200 answer has an empty body. A
// request without a sample throws a StateError. `i18n` returns 3.x's
// zh.json text. The quality catalog, the seat and the recipe are left out:
// they need a live WebSocket and the master playlist, which no sample has.
// `_LegacyRoom`, `_LegacyArea` and `_LegacyCategory` are the parts of 3.x's
// models these parsers use. The output format is the legacy harness's
// (`roomProjection`, `errorProjection`, `{generator, value}`).
//
// 3.x parsed the watch page with package:html, which the workspace does not
// depend on, so this runs with a throwaway package configuration. From the
// repository root:
//
//   d=$(mktemp -d)
//   printf 'name: g\nenvironment:\n  sdk: ^3.9.0\ndependencies:\n  html: 0.15.6\n' > "$d/pubspec.yaml"
//   (cd "$d" && dart pub get)
//   dart --packages="$d/.dart_tool/package_config.json" fixtures/niconico/legacy_expected.dart
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;

const _root = 'fixtures/niconico';

void main() async {
  await _catalog();
  await _directory('S01-recent-req-p1', 'req');
  await _directory('S01-recent-face-p1', 'face');
  await _search();
  await _watch('S03-watch-user-live', 'lv351482868');
  await _watch('S03-watch-program-live', 'lv351482868');
  await _watch('S03-watch-user-ended', 'lv351482791');
  await _watch('S03-watch-channel', 'lv351292489');
  await _watch('S03-watch-notfound', 'lv1');
  _grant();
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _listings = [];
Map<String, dynamic>? _watchSample;

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _load({List<String> listings = const [], String? watch}) {
  _listings = [for (final sample in listings) _meta(sample)];
  _watchSample = watch == null ? null : _meta(watch);
}

({int status, String body}) _answer(Map<String, dynamic> meta) {
  final status = (meta['response'] as Map<String, dynamic>)['status'] as int;
  final body = File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync();
  return (status: status, body: status == 200 ? body : '');
}

/// 3.x's `_defaultRequest` over the samples (it did not follow redirects).
Future<({int status, String body})> _replay(Uri uri, Object? cancel) async {
  if (uri.path.startsWith('/watch/')) {
    final watch = _watchSample;
    if (watch == null) throw StateError('No recorded watch page for GET $uri');
    return _answer(watch);
  }
  for (final meta in _listings) {
    final recorded = Uri.parse((meta['request'] as Map)['url'] as String);
    if (recorded.host == uri.host &&
        recorded.path == uri.path &&
        jsonEncode(recorded.queryParameters) == jsonEncode(uri.queryParameters)) {
      return _answer(meta);
    }
  }
  throw StateError('No recorded sample for GET $uri');
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

Map<String, dynamic> _page(LiveDirectoryPage page) => {
  'page': page.page,
  'hasMore': page.hasMore,
  'rooms': _rooms(page.rooms),
};

NiconicoSite _site() {
  final api = NiconicoApi(request: _replay);
  return NiconicoSite(
    api: api,
    directory: NiconicoDirectory(api: api),
  );
}

// Samples ---------------------------------------------------------------------

/// The one category (pages 1 and 2), the recommendation page (the "common"
/// tab) through the directory pager and the legacy list call.
Future<void> _catalog() async {
  _load(listings: ['S01-recent-common-p1']);
  final site = _site();
  _write('S01-recent-common-p1', 'NiconicoSite.getCategores + getDirectoryPage + getRecommendRooms', {
    'getCategores': {
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
    },
    'getDirectoryPage': await _outcome(() => site.getDirectoryPage(page: 1), _page),
    'getRecommendRooms': await _outcome(
      () => site.getRecommendRooms(page: 1, pageSize: 30),
      (rooms) => [for (final room in rooms) room.roomId],
    ),
  });
}

/// A tab's first page through the directory pager and the legacy list call.
Future<void> _directory(String sample, String tab) async {
  _load(listings: [sample]);
  final site = _site();
  final area = (await site.getCategores(1, 30)).single.children.firstWhere((area) => area.areaId == tab);
  _write(sample, 'NiconicoSite.getDirectoryPage + getCategoryRooms (tab $tab)', {
    'getDirectoryPage': await _outcome(() => site.getDirectoryPage(page: 1, category: area), _page),
    'getCategoryRooms': await _outcome(
      () => site.getCategoryRooms(area, page: 1, pageSize: 30),
      (rooms) => [for (final room in rooms) room.roomId],
    ),
  });
}

/// The search page's request (`pageSize: 20`, 3.x's search controller) and
/// the directory's paging answer for it.
Future<void> _search() async {
  _load(listings: ['S02-search']);
  final api = NiconicoApi(request: _replay);
  final site = NiconicoSite(
    api: api,
    directory: NiconicoDirectory(api: api),
  );
  _write('S02-search', 'NiconicoSite.searchRooms (pageSize 20) + NiconicoDirectory.search', {
    'searchRooms': await _outcome(() => site.searchRooms('ゲーム', page: 1, pageSize: 20), _rooms),
    'hasMore': await _outcome(() => NiconicoDirectory(api: api).search('ゲーム', page: 1), (page) => page.hasMore),
  });
}

/// A watch page as the room of [programId] at every depth, and what 3.x's
/// watch parser kept for the seat.
Future<void> _watch(String sample, String programId) async {
  _load(watch: sample);
  final site = _site();
  _write(
    sample,
    'NiconicoSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
    'NiconicoApi.room ($programId)',
    {
      'getRoomDetail': await _outcome(
        () => site.getRoomDetail(roomId: programId, platform: 'niconico'),
        _roomProjection,
      ),
      'getRoomDetailForRefresh': await _outcome(
        () => site.getRoomDetailForRefresh(roomId: programId, platform: 'niconico'),
        _roomProjection,
      ),
      'getRoomDetailForRecording': await _outcome(
        () => site.getRoomDetailForRecording(roomId: programId, platform: 'niconico'),
        _roomProjection,
      ),
      'getLiveStatus': await _outcome(
        () => site.getLiveStatus(platform: 'niconico', roomId: programId),
        (live) => live,
      ),
      'watch': await _outcome(
        () => NiconicoApi(request: _replay).room(programId),
        (watch) => {
          'status': watch.status.name,
          'access': watch.access.name,
          'reportedWatchCount': watch.reportedWatchCount,
          'webSocketUri': watch.webSocketUri?.toString(),
        },
      ),
    },
  );
}

/// The `stream` message of the recorded seat: the grant 3.x kept and the
/// cookies it sent for the master, a video segment and a key, at the time
/// of recording.
void _grant() {
  const sample = 'seat/S04-seat';
  final meta = _meta(sample);
  final capturedAt = DateTime.parse(meta['capturedAt'] as String);
  Map<String, dynamic>? stream;
  for (final line in File('$_root/$sample/frames.jsonl').readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final frame = jsonDecode(line) as Map<String, dynamic>;
    if (frame['dir'] != 'in') continue;
    final message = jsonDecode(frame['text'] as String) as Map<String, dynamic>;
    if (message['type'] == 'stream') stream = message['data'] as Map<String, dynamic>;
  }
  final grant = NiconicoStream.parse(stream!, now: () => capturedAt);
  final program = grant.uri.pathSegments[2];
  final origin = Uri.parse('https://livedelivery.dlive.nicovideo.jp');
  final video = origin.resolve('/hls/segments/$program/video/1.cmfv');
  final audio = origin.resolve('/hls/segments/$program/audio/1.cmfa');
  final key = origin.resolve('/hls/keys/$program/${grant.uri.pathSegments[3]}/1.key');
  final sessionKey = origin.resolve('/hls/keys/$program/1.key');
  _write(sample, 'NiconicoStream.parse (the stream frame, now = capturedAt) + cookieHeaderFor', {
    'uri': grant.uri.toString(),
    'quality': grant.quality,
    'availableQualities': grant.availableQualities,
    'retainedCookieCount': grant.retainedCookieCount,
    'cookieHeaderFor': {
      'master': grant.cookieHeaderFor(grant.uri),
      'video': grant.cookieHeaderFor(video),
      'audio': grant.cookieHeaderFor(audio),
      'key': grant.cookieHeaderFor(key),
      'sessionKey': grant.cookieHeaderFor(sessionKey),
    },
  });
}

// 3.x models (the parts the niconico parsers use) ----------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

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

class LiveDirectoryPage {
  LiveDirectoryPage({required Iterable<_LegacyRoom> rooms, required this.page, required this.hasMore, this.nextCursor})
    : rooms = List.unmodifiable(rooms);
  final List<_LegacyRoom> rooms;
  final int page;
  final bool hasMore;
  final String? nextCursor;
}

typedef LiveRoom = _LegacyRoom;

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

/// 3.x's zh.json text for the keys the adapter reads.
String i18n(String key) =>
    const {
      'niconico_login_required': '此节目要求登录官方站点。',
      'niconico_region_restricted': '此节目设有地区访问限制。',
      'niconico_access_restricted': '此节目的当前观看权限受限。',
      'niconico_scheduled': '节目尚未开始。',
      'niconico_category_common': '综合',
      'niconico_category_try': '创作与挑战',
      'niconico_category_live': '游戏',
      'niconico_category_req': '视频介绍',
      'niconico_category_face': '露脸直播',
      'niconico_category_totu': '连麦互动',
      'niconico_category_vtuber': 'VTuber',
      'niconico_program_scope': '收藏对应本次节目，主播的新节目需重新添加；弹幕暂未接入。',
    }[key] ??
    (throw StateError('No zh.json text for $key'));

// 3.x's niconico adapter (legacy/lib/core/site/niconico/) ---------------------
//
// Unchanged apart from the model names above and the transport: no Dio, so
// `CancelToken` is `Object?`, and `_defaultRequest` / `readBody` (the
// streamed 2 MiB body reader) and `withRequestCancellation` are left out;
// `_load` keeps the same deadline and failure mapping and lets the harness's
// StateError (a request without a sample) through instead of reporting it as
// a transport failure.

enum NiconicoFailure {
  transport,
  access,
  missing,
  rateLimited,
  service,
  schema,
  identity,
  cancelled,
  notLive,
  sessionClosed,
  sessionError,
  cleanup,
}

class NiconicoException implements Exception {
  const NiconicoException(this.kind);
  final NiconicoFailure kind;
  @override
  String toString() => 'Niconico ${kind.name}';
}

enum NiconicoStatus { scheduled, onAir, ended }

enum NiconicoAccess { allowed, loginRequired, regionRestricted, denied }

class NiconicoWatch {
  const NiconicoWatch({
    required this.programId,
    required this.title,
    required this.broadcaster,
    required this.status,
    required this.access,
    required this.reportedWatchCount,
    required this.webSocketUri,
    this.cover,
    this.avatar,
  });

  static const responseLimit = 2 * 1024 * 1024;
  final String programId;
  final String title;
  final String broadcaster;
  final NiconicoStatus status;
  final NiconicoAccess access;
  final int? reportedWatchCount;
  final Uri? webSocketUri;
  final String? cover;
  final String? avatar;

  static String validateProgramId(String id) {
    if (!RegExp(r'^lv[1-9][0-9]{0,17}$').hasMatch(id)) {
      throw const NiconicoException(NiconicoFailure.identity);
    }
    return id;
  }

  static String parseInput(String input) {
    if (input.length > 2048) throw const NiconicoException(NiconicoFailure.identity);
    final value = input.trim();
    if (value.startsWith('lv')) return validateProgramId(value);
    final match = RegExp(r'^https://live\.nicovideo\.jp/watch/(lv[1-9][0-9]{0,17})(?:\?[^#\s]*)?(?:#[^\s]*)?$')
        .firstMatch(value);
    if (match == null) throw const NiconicoException(NiconicoFailure.identity);
    return validateProgramId(match.group(1)!);
  }

  static NiconicoWatch parsePage(String body, {required String programId}) {
    validateProgramId(programId);
    if (body.length > responseLimit || utf8.encode(body).length > responseLimit) {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    final nodes = html.parse(body).querySelectorAll('script#embedded-data');
    if (nodes.length != 1) throw const NiconicoException(NiconicoFailure.schema);
    final encoded = nodes.single.attributes['data-props'];
    if (encoded == null) throw const NiconicoException(NiconicoFailure.schema);
    try {
      return parseData(_object(jsonDecode(encoded)), programId: programId);
    } on FormatException {
      throw const NiconicoException(NiconicoFailure.schema);
    }
  }

  static NiconicoWatch parseData(Map<String, dynamic> data, {required String programId}) {
    validateProgramId(programId);
    final program = _object(data['program']);
    if (_text(program['nicoliveProgramId']) != programId) {
      throw const NiconicoException(NiconicoFailure.identity);
    }
    final status = switch (program['status']) {
      'RELEASED' => NiconicoStatus.scheduled,
      'ON_AIR' => NiconicoStatus.onAir,
      'ENDED' => NiconicoStatus.ended,
      _ => throw const NiconicoException(NiconicoFailure.schema),
    };
    final needsLogin = _boolean(_object(_object(data['programWatch'])['condition'])['needLogin']);
    final userWatch = _object(data['userProgramWatch']);
    final countryRestricted = _boolean(userWatch['isCountryRestrictionTarget']);
    final canWatch = _boolean(userWatch['canWatch']);
    final access = countryRestricted
        ? NiconicoAccess.regionRestricted
        : needsLogin
        ? NiconicoAccess.loginRequired
        : canWatch
        ? NiconicoAccess.allowed
        : NiconicoAccess.denied;
    final count = _object(program['statistics'])['watchCount'];
    if (count != null && (count is! int || count < 0 || count > 9007199254740991)) {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    Uri? socket;
    if (status == NiconicoStatus.onAir && access == NiconicoAccess.allowed) {
      final site = _object(data['site']);
      final raw = _text(_object(site['relive'])['webSocketUrl']);
      final frontend = site['frontendId'];
      if (frontend is! int || frontend <= 0 || frontend > 9999) {
        throw const NiconicoException(NiconicoFailure.schema);
      }
      final uri = Uri.tryParse(raw);
      if (raw.length > 8192 ||
          uri == null ||
          uri.scheme != 'wss' ||
          uri.host != 'a.live2.nicovideo.jp' ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.hasFragment ||
          !RegExp(r'^/(?:unama/)?wsapi/v2/watch/[1-9][0-9]*$').hasMatch(uri.path) ||
          !raw.startsWith('wss://a.live2.nicovideo.jp${uri.path}?') ||
          uri.queryParametersAll.values.any((values) => values.length != 1)) {
        throw const NiconicoException(NiconicoFailure.schema);
      }
      socket = uri.replace(queryParameters: {...uri.queryParameters, 'frontend_id': '$frontend'});
    }
    return NiconicoWatch(
      programId: programId,
      title: _text(program['title']),
      broadcaster: _text(_object(program['supplier'])['name']),
      status: status,
      access: access,
      reportedWatchCount: count as int?,
      webSocketUri: socket,
      cover: _screenshot(program['screenshot']) ?? _cover(program['thumbnail']),
      avatar: _avatar(_object(program['supplier'])['icons']),
    );
  }

  static String? _screenshot(Object? value) {
    if (value is! Map || value['urlSet'] is! Map) return null;
    final urls = value['urlSet'] as Map;
    return publicImage(urls['middle']) ?? publicImage(urls['large']) ?? publicImage(urls['small']);
  }

  static String? _avatar(Object? value) => value is Map ? publicImage(value['uri150x150']) : null;

  static String? _cover(Object? value) {
    if (value is! Map) return null;
    final huge = value['huge'];
    return publicImage(huge is Map ? huge['s640x360'] : null) ??
        publicImage(value['large']) ??
        publicImage(value['small']);
  }

  static String? publicImage(Object? value) {
    if (value is! String || value.length > 8192) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasPort || uri.hasFragment) return null;
    if (!(uri.host.endsWith('.nimg.jp') || uri.host.endsWith('.nicovideo.jp'))) return null;
    final origin = 'https://${uri.host}';
    if (value != origin && !value.startsWith('$origin/') && !value.startsWith('$origin?')) return null;
    return value;
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) throw const NiconicoException(NiconicoFailure.schema);
    return value;
  }

  static String _text(Object? value) {
    if (value is! String) throw const NiconicoException(NiconicoFailure.schema);
    return value;
  }

  static bool _boolean(Object? value) {
    if (value is! bool) throw const NiconicoException(NiconicoFailure.schema);
    return value;
  }
}

typedef NiconicoRequest = Future<({int status, String body})> Function(Uri uri, Object? cancel);

class NiconicoApi {
  NiconicoApi({required NiconicoRequest request, this.deadline = const Duration(seconds: 20)}) : _request = request;
  static const origin = 'https://live.nicovideo.jp';
  static const headers = {'Referer': '$origin/', 'User-Agent': 'Mozilla/5.0'};
  final NiconicoRequest _request;
  final Duration deadline;

  Future<NiconicoWatch> room(String roomId, {Object? cancel}) => _load((transport) async {
    NiconicoWatch.validateProgramId(roomId);
    final body = await _requestBody(Uri.parse('$origin/watch/$roomId'), transport);
    return NiconicoWatch.parsePage(body, programId: roomId);
  }, cancel);

  Future<String> listing({required String path, required Map<String, String> query, Object? cancel}) =>
      _load((transport) {
        if (!const {'/front/api/pages/recent/v1/programs', '/front/api/pages/search/v1/programs'}.contains(path)) {
          throw const NiconicoException(NiconicoFailure.schema);
        }
        return _requestBody(Uri.parse('$origin$path').replace(queryParameters: query), transport);
      }, cancel);

  Future<T> _load<T>(Future<T> Function(Object?) work, Object? cancel) async {
    try {
      return await work(null).timeout(deadline);
    } on TimeoutException {
      throw const NiconicoException(NiconicoFailure.transport);
    } on StateError {
      rethrow;
    } catch (error) {
      if (error is NiconicoException) rethrow;
      throw const NiconicoException(NiconicoFailure.transport);
    }
  }

  Future<String> _requestBody(Uri uri, Object? transport) async {
    final response = await _request(uri, transport);
    final failure = switch (response.status) {
      200 => null,
      401 || 403 || 406 => NiconicoFailure.access,
      404 => NiconicoFailure.missing,
      429 => NiconicoFailure.rateLimited,
      >= 500 => NiconicoFailure.service,
      _ => NiconicoFailure.transport,
    };
    if (failure != null) throw NiconicoException(failure);
    return response.body;
  }
}

class NiconicoDirectory {
  NiconicoDirectory({required NiconicoApi api}) : _api = api;
  final NiconicoApi _api;
  static const categories = ['common', 'try', 'live', 'req', 'face', 'totu', 'vtuber'];
  static const recentSize = 70;
  static const searchSize = 40;

  static void validatePage(int page) {
    if (page < 1 || page > 10000) throw const NiconicoException(NiconicoFailure.schema);
  }

  Future<LiveDirectoryPage> recent({int page = 1, String tab = 'common', Object? cancel}) async {
    validatePage(page);
    if (!categories.contains(tab)) throw const NiconicoException(NiconicoFailure.schema);
    final body = await _api.listing(
      path: '/front/api/pages/recent/v1/programs',
      query: {'tab': tab, 'offset': '${page - 1}', 'sortOrder': 'recentDesc'},
      cancel: cancel,
    );
    return parse(body, page: page, search: false);
  }

  Future<LiveDirectoryPage> search(String keyword, {int page = 1, Object? cancel}) async {
    validatePage(page);
    if (keyword.length > 500) throw const NiconicoException(NiconicoFailure.schema);
    final term = keyword.trim();
    if (term.isEmpty) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final body = await _api.listing(
      path: '/front/api/pages/search/v1/programs',
      query: {'keyword': term, 'column': 'main', 'status': 'onair', 'page': '$page', 'disableGrouping': 'true'},
      cancel: cancel,
    );
    return parse(body, page: page, search: true);
  }

  static LiveDirectoryPage parse(String body, {required int page, required bool search}) {
    validatePage(page);
    if (body.length > NiconicoWatch.responseLimit || utf8.encode(body).length > NiconicoWatch.responseLimit) {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    try {
      final root = _object(jsonDecode(body));
      final meta = _object(root['meta']);
      if (meta['statusCode'] != 200 || meta['errorCode'] != 'OK') {
        throw const NiconicoException(NiconicoFailure.service);
      }
      final data = search ? _object(root['data']) : meta;
      final total = _count(data['totalCount']);
      final rows = search ? data['programs'] : root['data'];
      final size = search ? searchSize : recentSize;
      if (rows is! List || rows.length > size || total == null || total < rows.length) {
        throw const NiconicoException(NiconicoFailure.schema);
      }
      final identities = <String>{};
      final rooms = <LiveRoom>[];
      for (final row in rows) {
        final room = _room(_object(row), search: search);
        if (!identities.add(room.roomId!)) throw const NiconicoException(NiconicoFailure.identity);
        rooms.add(room);
      }
      return LiveDirectoryPage(rooms: rooms, page: page, hasMore: total > page * size);
    } on FormatException {
      throw const NiconicoException(NiconicoFailure.schema);
    }
  }

  static LiveRoom _room(Map<String, dynamic> row, {required bool search}) {
    final id = NiconicoWatch.validateProgramId(_text(row[search ? 'nicoliveProgramId' : 'id']));
    if (NiconicoWatch.parseInput(_text(row['watchPageUrl'])) != id) {
      throw const NiconicoException(NiconicoFailure.identity);
    }
    if (row[search ? 'status' : 'liveCycle'] != 'ON_AIR') {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    if (!const {'community', 'channel', 'official'}.contains(row['providerType'])) {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    final provider = search ? row['supplier'] : row['programProvider'];
    final social = row['socialGroup'];
    final name = provider is Map ? provider['name'] : null;
    final nick = name ?? (social is Map ? social['name'] : null);
    Object? icon;
    if (provider is Map) {
      final icons = provider['icons'];
      icon = search ? (icons is Map ? icons['uri150x150'] : null) : provider['icon'];
    }
    icon ??= social is Map ? social['thumbnailUrl'] : null;
    final count = _count(_object(row['statistics'])['watchCount']);
    return LiveRoom(
      platform: 'niconico',
      roomId: id,
      title: _text(row['title']),
      nick: _text(nick),
      avatar: NiconicoWatch.publicImage(icon) ?? '',
      cover:
          NiconicoWatch.publicImage(row['flippedListingThumbnail']) ??
          NiconicoWatch.publicImage(row['listingThumbnail']) ??
          '',
      link: '${NiconicoApi.origin}/watch/$id',
      liveStatus: LiveStatus.live,
      totalViewers: count?.toString(),
      audienceMetricType: AudienceMetricType.totalViewers,
    );
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) throw const NiconicoException(NiconicoFailure.schema);
    return value;
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 8192) {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    return value;
  }

  static int? _count(Object? value) {
    if (value == null) return null;
    if (value is! int || value < 0 || value > 9007199254740991) {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    return value;
  }
}

/// 3.x's `NiconicoSite` without the quality catalog, the seat and the
/// recipe (see the header).
class NiconicoSite {
  NiconicoSite({required NiconicoApi api, required NiconicoDirectory directory}) : _api = api, _directory = directory;
  final NiconicoDirectory _directory;
  final NiconicoApi _api;
  String get id => 'niconico';
  String get name => 'niconico';

  String get directoryNoticeKey => 'niconico_directory_scope';

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    NiconicoDirectory.validatePage(page);
    _pageSize(pageSize);
    return page == 1
        ? [
            LiveCategory(
              id: id,
              name: name,
              children: [
                for (final tab in NiconicoDirectory.categories)
                  LiveArea(
                    platform: id,
                    areaType: 'recent',
                    areaId: tab,
                    areaName: i18n('niconico_category_$tab'),
                    typeName: name,
                  ),
              ],
            ),
          ]
        : [];
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, Object? cancel}) {
    if (category != null &&
        (category.platform != id ||
            category.areaType != 'recent' ||
            !NiconicoDirectory.categories.contains(category.areaId))) {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    return _directory.recent(page: page, tab: category?.areaId ?? 'common', cancel: cancel);
  }

  static void _pageSize(int pageSize) {
    if (pageSize < 1 || pageSize > 100) throw const NiconicoException(NiconicoFailure.schema);
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    _pageSize(pageSize);
    return (await getDirectoryPage(page: page)).rooms;
  }

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _pageSize(pageSize);
    return (await getDirectoryPage(page: page, category: category)).rooms;
  }

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    Object? cancel,
  }) async {
    _pageSize(pageSize);
    return (await _directory.search(keyword, page: page, cancel: cancel)).rooms;
  }

  String _identity(String roomId, String platform) {
    if (platform != id) throw const NiconicoException(NiconicoFailure.identity);
    return NiconicoWatch.validateProgramId(roomId);
  }

  Future<LiveRoom> _detail(String roomId, String platform) async {
    final programId = _identity(roomId, platform);
    final watch = await _api.room(programId);
    final notice = switch (watch.access) {
      NiconicoAccess.loginRequired => i18n('niconico_login_required'),
      NiconicoAccess.regionRestricted => i18n('niconico_region_restricted'),
      NiconicoAccess.denied => i18n('niconico_access_restricted'),
      NiconicoAccess.allowed => null,
    };
    return LiveRoom(
      platform: id,
      roomId: programId,
      title: watch.title,
      nick: watch.broadcaster,
      cover: watch.cover ?? '',
      avatar: watch.avatar ?? '',
      link: '${NiconicoApi.origin}/watch/$programId',
      liveStatus: watch.status == NiconicoStatus.onAir ? LiveStatus.live : LiveStatus.offline,
      totalViewers: watch.reportedWatchCount?.toString(),
      audienceMetricType: AudienceMetricType.totalViewers,
      notice: [
        if (watch.status == NiconicoStatus.scheduled) i18n('niconico_scheduled'),
        if (watch.status == NiconicoStatus.onAir && notice != null) notice,
        i18n('niconico_program_scope'),
      ].join(' '),
    );
  }

  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) => _detail(roomId, platform);
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      _detail(roomId, platform);
  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      _detail(roomId, platform);
  Future<bool> getLiveStatus({required String platform, required String roomId}) async =>
      (await _detail(roomId, platform)).isLiveNow;
}

class NiconicoStream {
  NiconicoStream._(this.uri, this.quality, this.availableQualities, this._cookies);
  final Uri uri;
  final String quality;
  final List<String> availableQualities;
  final HlsSessionCookies _cookies;
  bool _active = true;
  bool get isActive => _active;
  int get retainedCookieCount => _cookies.count;

  String? cookieHeaderFor(Uri target) {
    if (!_active) throw const NiconicoException(NiconicoFailure.sessionClosed);
    if (target.userInfo.isNotEmpty || target.hasFragment) return null;
    return _cookies.headerFor(target);
  }

  void close() {
    _active = false;
    _cookies.clear();
  }

  static NiconicoStream parse(Map<String, dynamic> data, {DateTime Function()? now}) {
    if (data['protocol'] != 'hls') throw const NiconicoException(NiconicoFailure.schema);
    final raw = data['uri'];
    final uri = raw is String && raw.length <= 8192 ? Uri.tryParse(raw) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'livedelivery.dlive.nicovideo.jp' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment ||
        !uri.path.startsWith('/hls/playlists/') ||
        !uri.path.endsWith('.m3u8') ||
        !(raw as String).startsWith('https://livedelivery.dlive.nicovideo.jp${uri.path}')) {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    final quality = data['quality'];
    final qualities = data['availableQualities'];
    final validQuality = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');
    if (quality is! String ||
        !validQuality.hasMatch(quality) ||
        qualities is! List ||
        qualities.isEmpty ||
        qualities.length > 32 ||
        qualities.any((value) => value is! String || !validQuality.hasMatch(value)) ||
        qualities.toSet().length != qualities.length ||
        !qualities.contains(quality)) {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    final rawCookies = data['cookies'];
    if (rawCookies is! List || rawCookies.length > HlsSessionCookies.maximumCount) {
      throw const NiconicoException(NiconicoFailure.schema);
    }
    final headers = <String>[];
    final keys = <(String, String)>{};
    var retainedSize = 0;
    for (final entry in rawCookies) {
      if (entry is! Map<String, dynamic>) throw const NiconicoException(NiconicoFailure.schema);
      final name = entry['name'];
      final value = entry['value'];
      final path = entry['path'];
      final domain = entry['domain'];
      final expires = entry['expires'];
      if (name is! String ||
          !RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(name) ||
          name.startsWith('__Host-') ||
          value is! String ||
          !RegExp(r'^[\x21-\x7e]*$').hasMatch(value) ||
          value.contains(';') ||
          value.contains('"') ||
          value.contains(r'\') ||
          path is! String ||
          !RegExp(r'^/hls/[A-Za-z0-9_/-]+$').hasMatch(path) ||
          (domain != 'nicovideo.jp' && domain != '.nicovideo.jp') ||
          entry['secure'] != true ||
          (expires != null && expires is! String) ||
          !keys.add((path, name))) {
        throw const NiconicoException(NiconicoFailure.schema);
      }
      DateTime? expiration;
      if (expires is String) {
        try {
          expiration = HttpDate.parse(expires);
        } catch (_) {
          throw const NiconicoException(NiconicoFailure.schema);
        }
      }
      final cookie = Cookie(name, value)
        ..domain = domain as String
        ..path = path
        ..secure = true
        ..expires = expiration;
      final header = cookie.toString();
      final size = uri.origin.length + name.length + value.length + path.length;
      retainedSize += size;
      if (header.length > HlsSessionCookies.maximumCookieCharacters ||
          size > HlsSessionCookies.maximumCookieCharacters ||
          retainedSize > HlsSessionCookies.maximumCharacters) {
        throw const NiconicoException(NiconicoFailure.schema);
      }
      headers.add(header);
    }
    final cookies = HlsSessionCookies(now: now)..receive(uri, headers);
    return NiconicoStream._(uri, quality, List<String>.unmodifiable(qualities.cast<String>()), cookies);
  }
}

// 3.x's legacy/lib/core/common/hls_session_cookies.dart ----------------------

class HlsSessionCookies {
  HlsSessionCookies({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const maximumCount = 64;
  static const maximumCharacters = 16 * 1024;
  static const maximumCookieCharacters = 4096;
  final DateTime Function() _now;
  final Map<(String, String, String), _SessionCookie> _cookies = {};
  int _sequence = 0;

  int get count => _cookies.length;
  int get retainedCharacters => _cookies.values.fold(0, (sum, cookie) => sum + cookie.size);

  void clear() => _cookies.clear();

  void receive(Uri uri, Iterable<String> values) {
    final now = _now();
    _prune(now);
    for (final value in values) {
      if (value.length > maximumCookieCharacters) continue;
      final Cookie cookie;
      try {
        cookie = Cookie.fromSetCookieValue(value);
      } on FormatException {
        continue;
      } on ArgumentError {
        continue;
      } on HttpException {
        continue;
      }
      if (cookie.name.isEmpty) continue;
      var domain = cookie.domain?.toLowerCase();
      if (domain != null) {
        if (domain.startsWith('.')) domain = domain.substring(1);
        final exact = uri.host == domain;
        final parent = InternetAddress.tryParse(uri.host) == null && uri.host.endsWith('.$domain');
        if (domain.isEmpty || (!exact && !parent)) continue;
      }
      if (cookie.secure && uri.scheme != 'https') continue;
      if (cookie.name.startsWith('__Secure-') && (!cookie.secure || uri.scheme != 'https')) continue;
      if (cookie.name.startsWith('__Host-') &&
          (!cookie.secure || uri.scheme != 'https' || domain != null || cookie.path != '/')) {
        continue;
      }
      final path = cookie.path?.startsWith('/') == true ? cookie.path! : _defaultPath(uri.path);
      final key = (uri.origin, path, cookie.name);
      final expires = cookie.maxAge == null
          ? cookie.expires
          : now.add(Duration(seconds: cookie.maxAge!.clamp(0, 365 * 24 * 60 * 60)));
      final previous = _cookies.remove(key);
      if (expires != null && !expires.isAfter(now)) continue;
      final entry = _SessionCookie(
        origin: uri.origin,
        path: path,
        name: cookie.name,
        value: cookie.value,
        expires: expires,
        sequence: previous?.sequence ?? _sequence++,
      );
      if (entry.size > maximumCookieCharacters) continue;
      _cookies[key] = entry;
      while (_cookies.length > maximumCount || retainedCharacters > maximumCharacters) {
        _cookies.remove(_cookies.keys.first);
      }
    }
  }

  String? headerFor(Uri uri, {String? initialHeader}) {
    _prune(_now());
    final selected =
        _cookies.values.where((cookie) => cookie.origin == uri.origin && _pathMatches(uri.path, cookie.path)).toList()
          ..sort((a, b) {
            final pathOrder = b.path.length.compareTo(a.path.length);
            return pathOrder != 0 ? pathOrder : a.sequence.compareTo(b.sequence);
          });
    final names = selected.map((cookie) => cookie.name).toSet();
    final initial = (initialHeader ?? '').split(';').map((pair) => pair.trim()).where((pair) {
      final separator = pair.indexOf('=');
      return separator > 0 && !names.contains(pair.substring(0, separator).trim());
    });
    final pairs = [...selected.map((cookie) => '${cookie.name}=${cookie.value}'), ...initial];
    return pairs.isEmpty ? null : pairs.join('; ');
  }

  void _prune(DateTime now) =>
      _cookies.removeWhere((_, cookie) => cookie.expires != null && !cookie.expires!.isAfter(now));

  static String _defaultPath(String path) {
    final lastSlash = path.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : path.substring(0, lastSlash);
  }

  static bool _pathMatches(String request, String cookie) =>
      request == cookie ||
      (request.startsWith(cookie) && (cookie.endsWith('/') || request.substring(cookie.length).startsWith('/')));
}

class _SessionCookie {
  const _SessionCookie({
    required this.origin,
    required this.path,
    required this.name,
    required this.value,
    required this.expires,
    required this.sequence,
  });

  final String origin;
  final String path;
  final String name;
  final String value;
  final DateTime? expires;
  final int sequence;
  int get size => origin.length + path.length + name.length + value.length;
}
