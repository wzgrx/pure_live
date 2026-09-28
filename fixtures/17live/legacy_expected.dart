// Writes expected.json for the 17LIVE samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.33-17live.md, "v3 的冻结输出").
//
// The archive has no 17LIVE expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below is 3.x's
// SeventeenLiveApi, SeventeenLiveLink and SeventeenLiveSite, copied from
// legacy/lib/core/site/seventeenlive/ (archive/v4). 3.x already injected its
// transport (`SeventeenLiveRequest`), so only that function is replaced: it
// answers from the samples by host, path and query, with the empty body 3.x
// read for any status other than 200 (`_defaultRequest` drained it). A
// request without a sample is a StateError; 3.x's `_fetch` would turn it
// into `transport`, so it is also kept aside and rethrown after the call: a
// missing sample fails the run.
//
// `_defaultRequest` and `readBody` (the network path) are left out; Dio's
// CancelToken is reduced to the members 3.x used. `SeventeenLiveSite` keeps
// its method bodies without `extends`, `implements`, `@override` and
// `getDanmaku` (`EmptyDanmaku`); its constructor needs the API injected.
// `getCategores` and `getCategoryRooms` were not overridden (3.x's LiveSite
// answered an empty list), so they are not called. `i18n` returns 3.x's
// zh.json text. 3.x's LiveRoom, LiveArea, LivePlayQuality,
// LivePlayUrlResolution and LiveDirectoryPage are reduced to the parts these
// classes use. The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`); every entry also records the
// requests it made.
//
// 3.x only ever asked for the JP sections; the TW page
// (`S02-sections-tw`) is run through the same parser by answering the JP
// request with it, as a second parity sample for the directory rules.
//
// Run from the repository root: dart run fixtures/17live/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint, unused_field, unused_element
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/17live';

const _live = '27484154';
const _offline = '28371376';
const _missing = '999999999';

void main() async {
  await _directory();
  await _taiwan();
  await _search('S03-search', '花音');
  await _search('S03-search-none', 'zxqvnothingfixture');
  await _room('S04-live-live', _live);
  await _room('S04-live-offline', _offline);
  await _room('S04-live-notfound', _missing);
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
Set<String> _unmatched = {};
final List<Uri> _requests = [];
final List<StateError> _missingSamples = [];

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync())
        as Map<String, dynamic>;

void _load(List<String> samples, {Set<String> unmatched = const {}}) {
  _samples = [for (final sample in samples) _meta(sample)];
  _unmatched = unmatched;
  _requests.clear();
}

Map<String, String> _query(Uri uri) => {
  for (final entry in uri.queryParameters.entries)
    if (!_unmatched.contains(entry.key)) entry.key: entry.value,
};

bool _sameQuery(Uri a, Uri b) {
  final left = _query(a);
  final right = _query(b);
  return left.length == right.length &&
      left.entries.every((entry) => right[entry.key] == entry.value);
}

/// 3.x's `_defaultRequest` over the samples: no redirect following, and the
/// body is read only for a 200.
Future<({int status, String body})> _replay(
  Uri uri,
  CancelToken? cancel,
) async {
  _requests.add(uri);
  final meta = _samples.where((meta) {
    final recorded = Uri.parse((meta['request'] as Map)['url'] as String);
    return recorded.host == uri.host &&
        recorded.path == uri.path &&
        _sameQuery(recorded, uri);
  }).firstOrNull;
  if (meta == null) {
    final error = StateError('No recorded sample for GET $uri');
    _missingSamples.add(error);
    throw error;
  }
  final status = (meta['response'] as Map<String, dynamic>)['status'] as int;
  if (status != 200) return (status: status, body: '');
  return (
    status: 200,
    body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync(),
  );
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

/// [body]'s projection with the requests it made (their URLs).
Future<Object?> _outcome<T>(
  Future<T> Function() body,
  Object? Function(T value) project,
) async {
  final before = _requests.length;
  Object? value;
  try {
    value = project(await body());
  } on StateError {
    rethrow;
  } on Object catch (error) {
    value = _errorProjection(error);
  }
  if (_missingSamples.isNotEmpty) throw _missingSamples.first;
  return {
    'requests': [for (final uri in _requests.skip(before)) uri.toString()],
    'value': value,
  };
}

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()..['link'] = room.link;
  json.removeWhere(
    (key, value) =>
        value == null ||
        (value is Map && value.isEmpty) ||
        (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [
  for (final room in rooms) _roomProjection(room),
];

Map<String, dynamic> _pageProjection(LiveDirectoryPage page) => {
  'page': page.page,
  'hasMore': page.hasMore,
  'nextCursor': page.nextCursor,
  'rooms': _rooms(page.rooms),
};

Map<String, dynamic> _qualityProjection(LivePlayQuality quality) => {
  'quality': quality.quality,
  'id': quality.id,
  'sort': quality.sort,
};

Map<String, dynamic> _resolutionProjection(LivePlayUrlResolution resolution) =>
    {
      'urls': resolution.urls,
      'appliedQualityData': resolution.appliedQualityData,
    };

SeventeenLiveSite _site() =>
    SeventeenLiveSite(api: SeventeenLiveApi(request: _replay));

// Samples ---------------------------------------------------------------------

/// The JP sections: page 1 by every entry 3.x had, the caller errors 3.x
/// refused before a request, and page 2 by cursor and by replay.
Future<void> _directory() async {
  _load(['S01-sections-jp', 'S01-sections-jp-p2']);
  final site = _site();
  final first = await site.getDirectoryPageAtCursor(page: 1);
  final card = first.rooms.first;
  final area = LiveArea(platform: '17live', areaId: 'JP');
  _write(
    'S01-sections-jp',
    'SeventeenLiveSite.getDirectoryPageAtCursor(1) + getDirectoryPage(1) + '
        'getRecommendRooms(1) + caller errors + getPlayQualites(list card)',
    {
      'directoryNoticeKey': site.directoryNoticeKey,
      'name': site.name,
      'getDirectoryPageAtCursor(1)': await _outcome(
        () => site.getDirectoryPageAtCursor(page: 1),
        _pageProjection,
      ),
      'getDirectoryPage(1)': await _outcome(
        () => site.getDirectoryPage(page: 1),
        _pageProjection,
      ),
      'getRecommendRooms(1)': await _outcome(
        () => site.getRecommendRooms(page: 1),
        _rooms,
      ),
      'getRecommendRooms(1, pageSize 5)': await _outcome(
        () => site.getRecommendRooms(page: 1, pageSize: 5),
        _rooms,
      ),
      'getRecommendRooms(1, pageSize 0)': await _outcome(
        () => site.getRecommendRooms(page: 1, pageSize: 0),
        _rooms,
      ),
      'getDirectoryPageAtCursor(0)': await _outcome(
        () => site.getDirectoryPageAtCursor(page: 0),
        _pageProjection,
      ),
      'getDirectoryPageAtCursor(1, cursor)': await _outcome(
        () => site.getDirectoryPageAtCursor(page: 1, cursor: 'x'),
        _pageProjection,
      ),
      'getDirectoryPageAtCursor(2, no cursor)': await _outcome(
        () => site.getDirectoryPageAtCursor(page: 2),
        _pageProjection,
      ),
      'getDirectoryPageAtCursor(2, blank cursor)': await _outcome(
        () => site.getDirectoryPageAtCursor(page: 2, cursor: ''),
        _pageProjection,
      ),
      'getDirectoryPageAtCursor(1, category)': await _outcome(
        () => site.getDirectoryPageAtCursor(page: 1, category: area),
        _pageProjection,
      ),
      'getDirectoryPage(0)': await _outcome(
        () => site.getDirectoryPage(page: 0),
        _pageProjection,
      ),
      'getDirectoryPage(21)': await _outcome(
        () => site.getDirectoryPage(page: 21),
        _pageProjection,
      ),
      'getPlayQualites(list card)': await _outcome(
        () => site.getPlayQualites(detail: card),
        (qualities) => [for (final q in qualities) _qualityProjection(q)],
      ),
    },
  );
  _write(
    'S01-sections-jp-p2',
    'SeventeenLiveSite.getDirectoryPageAtCursor(2, cursor of page 1) + '
        'getDirectoryPage(2) + getDirectoryPage(3)',
    {
      'cursor': first.nextCursor,
      'getDirectoryPageAtCursor(2)': await _outcome(
        () => site.getDirectoryPageAtCursor(page: 2, cursor: first.nextCursor),
        _pageProjection,
      ),
      'getDirectoryPage(2)': await _outcome(
        () => site.getDirectoryPage(page: 2),
        _pageProjection,
      ),
      'getDirectoryPage(3)': await _outcome(
        () => site.getDirectoryPage(page: 3),
        _pageProjection,
      ),
    },
  );
}

/// The TW page through 3.x's directory parser (3.x asked for JP only).
Future<void> _taiwan() async {
  _load(['S02-sections-tw'], unmatched: {'region'});
  final site = _site();
  _write(
    'S02-sections-tw',
    "SeventeenLiveSite.getDirectoryPageAtCursor(1) answered with the TW page "
        "(3.x only asked for region=JP; parser parity only)",
    {
      'getDirectoryPageAtCursor(1)': await _outcome(
        () => site.getDirectoryPageAtCursor(page: 1),
        _pageProjection,
      ),
    },
  );
}

Future<void> _search(String sample, String keyword) async {
  _load([sample]);
  final site = _site();
  _write(sample, 'SeventeenLiveSite.searchRooms', {
    'searchRooms': await _outcome(() => site.searchRooms(keyword), _rooms),
    'searchRooms(pageSize 1)': await _outcome(
      () => site.searchRooms(keyword, pageSize: 1),
      _rooms,
    ),
    'searchRooms(page 2)': await _outcome(
      () => site.searchRooms(keyword, page: 2),
      _rooms,
    ),
    'searchRooms(pageSize 0)': await _outcome(
      () => site.searchRooms(keyword, pageSize: 0),
      _rooms,
    ),
  });
}

/// Links 3.x's `SeventeenLiveLink` was asked about.
const _links = [
  'https://17.live/ja/live/27484154',
  'https://17.live/en/live/27484154',
  'https://17.live/live/27484154',
  'http://17.live/zh-Hant/live/27484154',
  'https://17.live/ja/live/27484154?lang=ja#chat',
  'https://17.live/ja/live/27484154/',
  'https://17.LIVE/JA/LIVE/27484154',
  '  https://17.live/ja/live/27484154  ',
  'https://17.live/ja/profile/r/27484154',
  'https://17.live/profile/r/27484154',
  'https://17.live/en-us/profile/r/27484154',
  'https://17.live:443/ja/live/27484154',
  'https://www.17.live/ja/live/27484154',
  'https://m.17.live/ja/live/27484154',
  'https://17.live/ja/live/0123',
  'https://17.live/ja/live/1234567890123',
  'https://17.live/ja/live/abc',
  'https://17.live/japan/live/27484154',
  'https://17.live/ja/profile/27484154',
  'https://17.live/ja/live/27484154/extra',
  'https://user@17.live/ja/live/27484154',
  'ftp://17.live/ja/live/27484154',
  'https://17.live/ja/live/%FF',
  'https://17.live/',
  '27484154',
  ' 27484154 ',
  '0',
  'not a link',
];

Map<String, Object?> _linkProjection() => {
  for (final link in _links)
    link: () {
      Object? guard(Object? Function() body) {
        try {
          return body();
        } on Object catch (error) {
          return _errorProjection(error);
        }
      }

      return {
        'parse': guard(() => SeventeenLiveLink.parse(link)),
        'parseOrId': guard(() => SeventeenLiveLink.parseOrId(link)),
        'normalizeRoomId': guard(() => SeventeenLiveLink.normalizeRoomId(link)),
      };
    }(),
};

/// Every entry 3.x had for one room: entry, refresh, recording, state,
/// qualities with their URLs, recovery, and the searches that find it.
Future<void> _room(String sample, String id) async {
  _load([sample]);
  final site = _site();
  final value = <String, Object?>{
    'getRoomDetail': await _outcome(
      () => site.getRoomDetail(roomId: id, platform: '17live'),
      _roomProjection,
    ),
    'getRoomDetailForRefresh': await _outcome(
      () => site.getRoomDetailForRefresh(roomId: id, platform: '17live'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _outcome(
      () => site.getRoomDetailForRecording(roomId: id, platform: '17live'),
      _roomProjection,
    ),
    'getLiveStatus': await _outcome(
      () => site.getLiveStatus(roomId: id, platform: '17live'),
      (live) => live,
    ),
    'getRoomDetail(other platform)': await _outcome(
      () => site.getRoomDetail(roomId: id, platform: 'pandalive'),
      _roomProjection,
    ),
    'searchRooms(id)': await _outcome(() => site.searchRooms(id), _rooms),
    'searchRooms(live link)': await _outcome(
      () => site.searchRooms(' https://17.live/ja/live/$id '),
      _rooms,
    ),
    'searchRooms(profile link)': await _outcome(
      () => site.searchRooms('https://17.live/en/profile/r/$id'),
      _rooms,
    ),
    'searchRooms(id, page 2)': await _outcome(
      () => site.searchRooms(id, page: 2),
      _rooms,
    ),
  };
  if (id == _live) {
    value['getRoomDetail(not a room id)'] = await _outcome(
      () => site.getRoomDetail(roomId: 'abc', platform: '17live'),
      _roomProjection,
    );
    value['mediaHeaders'] = SeventeenLiveApi.mediaHeaders(id);
    value['requestHeaders'] = SeventeenLiveApi.requestHeaders(id);
    value['catalogHeaders'] = SeventeenLiveApi.catalogHeaders();
    value['links'] = _linkProjection();
  }
  try {
    final detail = await site.getRoomDetail(roomId: id, platform: '17live');
    value['getPlayQualites'] = await _outcome(
      () => site.getPlayQualites(detail: detail),
      (qualities) => [for (final q in qualities) _qualityProjection(q)],
    );
    final qualities = await site.getPlayQualites(detail: detail);
    final requested = qualities.isEmpty
        ? [LivePlayQuality(quality: 'hd', id: 'hd')]
        : qualities;
    value['getPlayUrls'] = {
      for (final quality in requested)
        '${quality.id}': await _outcome(
          () => site.getPlayUrls(detail: detail, quality: quality),
          (urls) => urls,
        ),
    };
    value['resolvePlayUrlsRaw'] = {
      for (final quality in requested)
        '${quality.id}': await _outcome(
          () => site.resolvePlayUrlsRaw(detail: detail, quality: quality),
          _resolutionProjection,
        ),
    };
    value['resolvePlayUrlsForRecoveryRaw'] = {
      for (final quality in requested)
        '${quality.id}': await _outcome(
          () => site.resolvePlayUrlsForRecoveryRaw(
            detail: detail,
            quality: quality,
          ),
          _resolutionProjection,
        ),
    };
    value['getPlayUrls(unknown quality)'] = await _outcome(
      () => site.getPlayUrls(
        detail: detail,
        quality: LivePlayQuality(quality: 'x', id: 'source'),
      ),
      (urls) => urls,
    );
  } on StateError {
    rethrow;
  } on Object {
    // Room entry failed: recorded above as getRoomDetail.
  }
  _write(
    sample,
    'SeventeenLiveSite.getRoomDetail + getRoomDetailForRefresh + '
    'getRoomDetailForRecording + getLiveStatus + searchRooms + '
    'getPlayQualites + getPlayUrls + resolvePlayUrlsRaw + '
    'resolvePlayUrlsForRecoveryRaw',
    value,
  );
}

// 3.x's i18n (assets/translations/zh.json) ----------------------------------------

const Map<String, String> _zh = {
  'seventeen_directory_scope': '官网日本区公开推荐按原生游标加载，不代表全站目录；搜索覆盖官网当前直播窗口，精确房间号与官方直播间/主播主页链接继续支持，未开播昵称不在搜索结果中。',
  'seventeen_age_notice': '17LIVE 要求观看者年满 18 周岁。',
  'seventeen_audio_room': '音频直播',
  'seventeen_quality_enhanced': '增强高清',
  'seventeen_quality_hd': '高清',
  'seventeen_quality_h264': 'H.264',
  'seventeen_quality_standard': '标准',
};

String i18n(String key) =>
    _zh[key] ?? (throw StateError('No zh.json text for $key'));

// Dio (only what the copied code names) ---------------------------------------

class CancelToken {
  bool get isCancelled => false;
  static bool isCancel(Object error) => false;
}

class DioException implements Exception {}

// 3.x models (the parts the 17LIVE adapter uses) ------------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType {
  popularity,
  onlineViewers,
  totalViewers,
  followers,
  unknown,
}

class LiveArea {
  LiveArea({
    this.platform,
    this.areaType,
    this.typeName,
    this.areaId,
    this.areaName,
    this.areaPic,
    this.shortName,
  });

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
  LiveDirectoryPage({
    required Iterable<LiveRoom> rooms,
    required this.page,
    required this.hasMore,
    this.nextCursor,
  }) : rooms = List.unmodifiable(rooms);
  final List<LiveRoom> rooms;
  final int page;
  final bool hasMore;
  final String? nextCursor;
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
  }) : liveStatus =
           liveStatus ??
           _legacyStatusToLiveStatus(status: status, isRecord: isRecord);

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

  static LiveStatus? _legacyStatusToLiveStatus({
    required bool? status,
    required bool? isRecord,
  }) {
    if (isRecord == true) return LiveStatus.replay;
    if (status == true) return LiveStatus.live;
    if (status == false) return LiveStatus.offline;
    return null;
  }

  String get normalizedPlatformId => (platform ?? '').trim().toLowerCase();

  LiveStatus get effectiveLiveStatus {
    if (isRecord == true || liveStatus == LiveStatus.replay)
      return LiveStatus.replay;
    final canonical = liveStatus;
    if (canonical != null) return canonical;
    return _legacyStatusToLiveStatus(status: status, isRecord: isRecord) ??
        LiveStatus.unknown;
  }

  bool get isLiveNow => effectiveLiveStatus == LiveStatus.live;

  bool get isExplicitlyOfflineNow =>
      effectiveLiveStatus == LiveStatus.offline ||
      effectiveLiveStatus == LiveStatus.banned;

  AudienceMetricType get effectiveAudienceMetricType {
    if (audienceMetricType != null &&
        audienceMetricType != AudienceMetricType.unknown)
      return audienceMetricType!;
    return switch (normalizedPlatformId) {
      'bilibili' ||
      'douyu' ||
      'huya' ||
      'cc' ||
      'yy' ||
      'missevan' => AudienceMetricType.popularity,
      'kuaishou' || 'twitch' || 'soop' => AudienceMetricType.onlineViewers,
      'douyin' => AudienceMetricType.totalViewers,
      _ => AudienceMetricType.unknown,
    };
  }

  /// 3.x's `HttpHeaderPolicy.normalize` for these values: lower-case names,
  /// sorted.
  Map<String, String> get _headers {
    final entries = [
      for (final entry in httpHeaders.entries)
        MapEntry(entry.key.toLowerCase(), entry.value.trim()),
    ]..sort((a, b) => a.key.compareTo(b.key));
    return {for (final entry in entries) entry.key: entry.value};
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
    'httpHeaders': _headers,
  };
}

// 3.x's seventeenlive_link.dart (unchanged) -----------------------------------

class SeventeenLiveLink {
  const SeventeenLiveLink._();

  static String? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != '17.live') {
      return null;
    }
    final segments = uri.pathSegments
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (segments.length == 2 && segments[0].toLowerCase() == 'live') {
      return normalizeRoomId(segments[1]);
    }
    if (segments.length == 3 &&
        _locale(segments[0]) &&
        segments[1].toLowerCase() == 'live') {
      return normalizeRoomId(segments[2]);
    }
    if (segments.length == 3 &&
        segments[0].toLowerCase() == 'profile' &&
        segments[1].toLowerCase() == 'r') {
      return normalizeRoomId(segments[2]);
    }
    if (segments.length == 4 &&
        _locale(segments[0]) &&
        segments[1].toLowerCase() == 'profile' &&
        segments[2].toLowerCase() == 'r') {
      return normalizeRoomId(segments[3]);
    }
    return null;
  }

  static String? parseOrId(String raw) => parse(raw) ?? normalizeRoomId(raw);

  static String? normalizeRoomId(String raw) {
    final roomId = raw.trim();
    return RegExp(r'^[1-9][0-9]{0,11}$').hasMatch(roomId) ? roomId : null;
  }

  static String url(String raw) {
    final roomId = normalizeRoomId(raw);
    if (roomId == null) throw const FormatException('Invalid 17LIVE room ID');
    return 'https://17.live/en/live/$roomId';
  }

  static bool _locale(String value) => RegExp(
    r'^[a-z]{2}(?:-[a-z]{2,4})?$',
    caseSensitive: false,
  ).hasMatch(value);
}

// 3.x's seventeenlive_api.dart (transport injected; `_defaultRequest` and
// `readBody` left out) --------------------------------------------------------

enum SeventeenLiveFailure {
  transport,
  access,
  rateLimited,
  service,
  missing,
  schema,
  cancelled,
  identity,
  unknownState,
  mediaUnavailable,
}

class SeventeenLiveException implements Exception {
  const SeventeenLiveException(this.kind);
  final SeventeenLiveFailure kind;

  @override
  String toString() => '17LIVE ${kind.name}';
}

enum SeventeenLiveState { live, offline, unknown }

class SeventeenLiveStream {
  const SeventeenLiveStream({required this.qualityId, required this.urls});
  final String qualityId;
  final List<Uri> urls;
}

class SeventeenLiveDirectoryPage {
  SeventeenLiveDirectoryPage({
    required Iterable<SeventeenLiveRoom> rooms,
    required this.nextCursor,
  }) : rooms = List.unmodifiable(rooms);

  final List<SeventeenLiveRoom> rooms;
  final String? nextCursor;
  bool get hasMore => nextCursor != null;
}

class SeventeenLiveRoom {
  const SeventeenLiveRoom({
    required this.roomId,
    required this.userId,
    required this.nickname,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.bio,
    required this.followers,
    required this.liveViewers,
    required this.sessionViewers,
    required this.audioOnly,
    required this.state,
    required this.streams,
  });

  final String roomId;
  final String userId;
  final String nickname;
  final String title;
  final String avatar;
  final String cover;
  final String bio;
  final int? followers;
  final int? liveViewers;
  final int? sessionViewers;
  final bool audioOnly;
  final SeventeenLiveState state;
  final List<SeventeenLiveStream> streams;
}

typedef SeventeenLiveRequest = Future<({int status, String body})> Function(
  Uri uri,
  CancelToken? cancel,
);

class SeventeenLiveApi {
  SeventeenLiveApi({required SeventeenLiveRequest request})
    : _request = request;

  static const origin = 'https://17.live';
  static const apiOrigin = 'https://api-dsa.17app.co';
  static const responseLimit = 4 * 1024 * 1024;
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  static Map<String, String> requestHeaders(String roomId) => {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Origin': origin,
    'Referer': SeventeenLiveLink.url(roomId),
  };

  static Map<String, String> catalogHeaders() => {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'ja-JP,ja;q=0.9,en;q=0.8',
    'Origin': origin,
    'Referer': '$origin/',
  };

  static Map<String, String> mediaHeaders(String roomId) => {
    'User-Agent': userAgent,
    'Origin': origin,
    'Referer': SeventeenLiveLink.url(roomId),
  };

  final SeventeenLiveRequest _request;

  Future<SeventeenLiveRoom> room(
    String rawRoomId, {
    CancelToken? cancel,
  }) async {
    final roomId = SeventeenLiveLink.normalizeRoomId(rawRoomId);
    if (roomId == null)
      throw const SeventeenLiveException(SeventeenLiveFailure.identity);
    final body = await _fetch(
      Uri.parse('$apiOrigin/api/v1/lives/$roomId'),
      cancel,
    );
    try {
      return _room(roomId, _object(jsonDecode(body)));
    } on FormatException {
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    }
  }

  /// The website's public JP recommendation sections use an opaque cursor.
  /// Banner, archive and VOD sections are not current-live directory rows.
  Future<SeventeenLiveDirectoryPage> directory({
    String? cursor,
    CancelToken? cancel,
  }) async {
    if (cursor != null &&
        (cursor.isEmpty ||
            cursor.length > 512 ||
            cursor.contains(RegExp(r'[\x00-\x1f]')))) {
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    }
    final uri = Uri.parse('$apiOrigin/api/v1/sections').replace(
      queryParameters: {
        'count': '20',
        'typeTab': '2',
        'region': 'JP',
        'cursor': cursor ?? '',
      },
    );
    final body = await _fetch(uri, cancel);
    try {
      final data = _object(jsonDecode(body));
      final sections = _list(data['sections'], max: 80);
      final seen = <String>{};
      final rooms = <SeventeenLiveRoom>[];
      for (final raw in sections) {
        final section = _object(raw);
        if (const {'TopBanner', 'ArchiveVideo', 'Vod'}.contains(section['id']))
          continue;
        for (final rawGrid in _list(section['grids'] ?? const [], max: 200)) {
          final stream = _object(rawGrid)['stream'];
          if (stream == null) continue;
          try {
            final row = _object(stream);
            final roomId = _positiveInt(row['liveStreamID']).toString();
            final room = _room(
              roomId,
              row,
              requireOwnerRoomId: false,
              includeStreams: false,
            );
            if (room.state == SeventeenLiveState.live && seen.add(roomId))
              rooms.add(room);
          } on SeventeenLiveException {
            // An individual stale or malformed recommendation must not hide
            // the other independently identified live rooms in this section.
          }
        }
      }
      final rawCursor = data['cursor'];
      if (rawCursor != null && rawCursor is! String)
        throw const SeventeenLiveException(SeventeenLiveFailure.schema);
      final nextCursor =
          rawCursor is String && rawCursor.isNotEmpty && rawCursor != cursor
          ? rawCursor
          : null;
      if (nextCursor != null &&
          (nextCursor.length > 512 ||
              nextCursor.contains(RegExp(r'[\x00-\x1f]')))) {
        throw const SeventeenLiveException(SeventeenLiveFailure.schema);
      }
      return SeventeenLiveDirectoryPage(rooms: rooms, nextCursor: nextCursor);
    } on FormatException {
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    }
  }

  /// The website exposes a bounded current-live search result, without a
  /// server cursor or offline profiles. Exact room links remain a separate path.
  Future<List<SeventeenLiveRoom>> searchCurrentLive(
    String keyword, {
    CancelToken? cancel,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty || query.length > 100)
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    final uri = Uri.parse('$apiOrigin/api/v1/liveStreams/search')
        .replace(queryParameters: {'query': query});
    final body = await _fetch(uri, cancel);
    try {
      final rows = _list(jsonDecode(body), max: 100);
      final seen = <String>{};
      final rooms = <SeventeenLiveRoom>[];
      for (final raw in rows) {
        try {
          final row = _object(raw);
          final roomId = _positiveInt(row['liveStreamID']).toString();
          final room = _room(roomId, row, includeStreams: false);
          if (room.state == SeventeenLiveState.live && seen.add(roomId))
            rooms.add(room);
        } on SeventeenLiveException {
          // Search cards may disappear between the website index and read.
        }
      }
      return List.unmodifiable(rooms);
    } on FormatException {
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    }
  }

  Future<String> _fetch(Uri uri, CancelToken? cancel) async {
    if (cancel?.isCancelled == true)
      throw const SeventeenLiveException(SeventeenLiveFailure.cancelled);
    late final ({int status, String body}) response;
    try {
      response = await _request(uri, cancel);
    } catch (error) {
      if (cancel?.isCancelled == true ||
          (error is DioException && CancelToken.isCancel(error))) {
        throw const SeventeenLiveException(SeventeenLiveFailure.cancelled);
      }
      if (error is SeventeenLiveException) rethrow;
      throw const SeventeenLiveException(SeventeenLiveFailure.transport);
    }
    final failure = switch (response.status) {
      200 => null,
      400 => SeventeenLiveFailure.schema,
      401 || 403 => SeventeenLiveFailure.access,
      404 => SeventeenLiveFailure.missing,
      420 || 429 => SeventeenLiveFailure.rateLimited,
      >= 500 => SeventeenLiveFailure.service,
      _ => SeventeenLiveFailure.transport,
    };
    if (failure != null) throw SeventeenLiveException(failure);
    if (response.body.length > responseLimit)
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    return response.body;
  }

  static SeventeenLiveRoom _room(
    String requestedRoomId,
    Map<String, dynamic> data, {
    bool requireOwnerRoomId = true,
    bool includeStreams = true,
  }) {
    final responseRoomId = _positiveInt(data['liveStreamID']).toString();
    final user = _object(data['userInfo']);
    final ownerRoomId = user['roomID'] == null
        ? null
        : _positiveInt(user['roomID']).toString();
    if (responseRoomId != requestedRoomId ||
        (requireOwnerRoomId && ownerRoomId != requestedRoomId) ||
        (ownerRoomId != null && ownerRoomId != requestedRoomId)) {
      throw const SeventeenLiveException(SeventeenLiveFailure.identity);
    }
    final userId = _text(data['userID']);
    if (_text(user['userID']) != userId)
      throw const SeventeenLiveException(SeventeenLiveFailure.identity);
    final status = _integer(data['status']);
    final state = switch (status) {
      2 => SeventeenLiveState.live,
      0 => SeventeenLiveState.offline,
      _ => SeventeenLiveState.unknown,
    };
    final nickname = _firstText([user['displayName'], user['openID']]);
    final title = _optionalText(data['caption']);
    final streams = includeStreams && state == SeventeenLiveState.live
        ? _streams(data)
        : const <SeventeenLiveStream>[];
    return SeventeenLiveRoom(
      roomId: requestedRoomId,
      userId: userId,
      nickname: nickname,
      title: title.isEmpty ? nickname : title,
      avatar: _image(user['picture']),
      cover: _image(data['coverPhoto'] ?? data['thumbnail']),
      bio: _optionalText(user['bio']),
      followers: _optionalNonNegativeInt(user['followerCount']),
      liveViewers: state == SeventeenLiveState.live
          ? _optionalNonNegativeInt(data['liveViewerCount'])
          : null,
      sessionViewers: state == SeventeenLiveState.live
          ? _optionalNonNegativeInt(data['viewerCount'])
          : null,
      audioOnly: _integer(data['audioOnly']) == 1,
      state: state,
      streams: streams,
    );
  }

  static List<SeventeenLiveStream> _streams(Map<String, dynamic> data) {
    Object? rawProviders;
    final pull = data['pullURLsInfo'];
    if (pull is Map) rawProviders = _object(pull)['rtmpURLs'];
    rawProviders ??= data['rtmpUrls'];
    if (rawProviders == null) return const [];
    final providers = _list(rawProviders, max: 16);
    final qualities = <String, List<Uri>>{};
    final seen = <String, Set<Uri>>{};
    void add(String qualityId, Object? value) {
      if (value == null || value == '') return;
      if (value is! String)
        throw const SeventeenLiveException(SeventeenLiveFailure.schema);
      final uri = _mediaUri(value);
      if (uri == null || !(seen[qualityId] ??= <Uri>{}).add(uri)) return;
      (qualities[qualityId] ??= <Uri>[]).add(uri);
    }

    for (final raw in providers) {
      final provider = _object(raw);
      add('enhanced', provider['urlQualityEnhancedHD']);
      add('hd', provider['urlLowBitrateHD']);
      add('hd', provider['webUrl']);
      add('hd', provider['url']);
      add('h264', provider['url264']);
      add('standard', provider['urlLowQuality']);
      add('standard', provider['webUrlLowQuality']);
      add('standard', provider['urlHighQuality']);
    }
    const order = ['enhanced', 'hd', 'h264', 'standard'];
    return List.unmodifiable(
      order.where(qualities.containsKey).map((qualityId) {
        return SeventeenLiveStream(
          qualityId: qualityId,
          urls: List.unmodifiable(qualities[qualityId]!),
        );
      }),
    );
  }

  static Uri? _mediaUri(String raw) {
    if (raw.isEmpty ||
        raw.length > 65536 ||
        raw.contains(RegExp(r'[\s\x00-\x1f]')))
      return null;
    final uri = Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !host.endsWith('.17app.co') ||
        !host.contains('pull-rtmp') ||
        !uri.path.toLowerCase().endsWith('.flv')) {
      return null;
    }
    return uri;
  }

  static String _image(Object? value) {
    if (value is! String || value.isEmpty || value.length > 8192) return '';
    Uri? uri = Uri.tryParse(value);
    if (uri != null && !uri.hasScheme) {
      if (value.contains('..') ||
          !RegExp(r'^[a-zA-Z0-9._/?=&-]+$').hasMatch(value))
        return '';
      uri = Uri.https(
        'cdn.17app.co',
        value.startsWith('/') ? value : '/$value',
      );
    }
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !const {'cdn.17app.co', 'assets-17app.akamaized.net'}.contains(host)) {
      return '';
    }
    return uri.replace(scheme: 'https').toString();
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map)
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<dynamic> _list(Object? value, {required int max}) {
    if (value is! List || value.length > max)
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    return value;
  }

  static int? _integer(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  static int _positiveInt(Object? value) {
    final result = _integer(value);
    if (result == null || result <= 0)
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    return result;
  }

  static int? _optionalNonNegativeInt(Object? value) {
    if (value == null || value == '') return null;
    final result = _integer(value);
    if (result == null || result < 0)
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    return result;
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 8192) {
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    }
    return value.trim();
  }

  static String _optionalText(Object? value) {
    if (value == null || value == '') return '';
    if (value is! String || value.length > 131072) {
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    }
    return value.trim();
  }

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = _optionalText(value);
      if (text.isNotEmpty) return text;
    }
    throw const SeventeenLiveException(SeventeenLiveFailure.schema);
  }
}

// 3.x's seventeenlive_site.dart (the LiveSite interfaces and the danmaku left
// out) --------------------------------------------------------------------------

class SeventeenLiveSite {
  SeventeenLiveSite({required SeventeenLiveApi api}) : _api = api;

  final SeventeenLiveApi _api;

  String get id => '17live';

  String get name => '17LIVE';

  String get directoryNoticeKey => 'seventeen_directory_scope';

  Future<LiveDirectoryPage> getDirectoryPageAtCursor({
    required int page,
    String? cursor,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    if (page < 1 ||
        (page == 1 && cursor != null) ||
        (page > 1 && cursor == null) ||
        category != null) {
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    }
    final result = await _api.directory(cursor: cursor, cancel: cancel);
    return LiveDirectoryPage(
      page: page,
      rooms: result.rooms.map((room) => _card(room, includeMedia: false)),
      hasMore: result.hasMore,
      nextCursor: result.nextCursor,
    );
  }

  /// Compatibility callers replay a short prefix; catalogue controllers use
  /// the cursor contract directly and own their refresh generation.
  Future<LiveDirectoryPage> getDirectoryPage({
    int page = 1,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    if (page < 1 || page > 20)
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    String? cursor;
    for (var current = 1; current <= page; current++) {
      final result = await getDirectoryPageAtCursor(
        page: current,
        cursor: cursor,
        category: category,
        cancel: cancel,
      );
      if (current == page) return result;
      if (!result.hasMore)
        return LiveDirectoryPage(page: page, hasMore: false, rooms: const []);
      cursor = result.nextCursor;
    }
    throw const SeventeenLiveException(SeventeenLiveFailure.schema);
  }

  Future<List<LiveRoom>> getRecommendRooms({
    int page = 1,
    int pageSize = 30,
  }) async {
    if (pageSize < 1)
      throw const SeventeenLiveException(SeventeenLiveFailure.schema);
    return (await getDirectoryPage(page: page)).rooms
        .take(pageSize)
        .toList(growable: false);
  }

  LiveRoom _card(SeventeenLiveRoom room, {required bool includeMedia}) =>
      LiveRoom(
        platform: id,
        roomId: room.roomId,
        userId: room.userId,
        nick: room.nickname,
        title: room.title,
        avatar: room.avatar,
        cover: room.cover,
        area: room.audioOnly ? i18n('seventeen_audio_room') : '',
        followers: room.followers?.toString(),
        introduction: room.bio,
        link: SeventeenLiveLink.url(room.roomId),
        liveStatus: switch (room.state) {
          SeventeenLiveState.live => LiveStatus.live,
          SeventeenLiveState.offline => LiveStatus.offline,
          SeventeenLiveState.unknown => LiveStatus.unknown,
        },
        watching: '',
        onlineViewers: room.liveViewers?.toString(),
        totalViewers: room.sessionViewers?.toString(),
        audienceMetricType: AudienceMetricType.onlineViewers,
        notice: i18n('seventeen_age_notice'),
        httpHeaders: SeventeenLiveApi.mediaHeaders(room.roomId),
        data: includeMedia ? room : null,
      );

  String _roomId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id)
      throw const SeventeenLiveException(SeventeenLiveFailure.identity);
    final normalized = SeventeenLiveLink.normalizeRoomId(roomId);
    if (normalized == null)
      throw const SeventeenLiveException(SeventeenLiveFailure.identity);
    return normalized;
  }

  Future<LiveRoom> _detail(
    String roomId,
    String platform, {
    required bool includeMedia,
  }) async {
    final data = await _api.room(_roomId(roomId, platform));
    if (includeMedia &&
        data.state == SeventeenLiveState.live &&
        data.streams.isEmpty) {
      throw const SeventeenLiveException(SeventeenLiveFailure.mediaUnavailable);
    }
    return _card(data, includeMedia: includeMedia);
  }

  Future<LiveRoom> getRoomDetail({
    required String roomId,
    required String platform,
  }) => _detail(roomId, platform, includeMedia: true);

  Future<LiveRoom> getRoomDetailForRecording({
    required String roomId,
    required String platform,
  }) => _detail(roomId, platform, includeMedia: true);

  Future<LiveRoom> getRoomDetailForRefresh({
    required String roomId,
    required String platform,
  }) => _detail(roomId, platform, includeMedia: false);

  Future<bool> getLiveStatus({
    required String platform,
    required String roomId,
  }) async {
    final room = await getRoomDetailForRefresh(
      roomId: roomId,
      platform: platform,
    );
    if (room.effectiveLiveStatus == LiveStatus.unknown) {
      throw const SeventeenLiveException(SeventeenLiveFailure.unknownState);
    }
    return room.isLiveNow;
  }

  Future<List<LiveRoom>> searchRooms(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) => searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page != 1 || pageSize < 1) return [];
    final roomId = SeventeenLiveLink.parseOrId(keyword);
    if (roomId != null) {
      try {
        return [
          _card(await _api.room(roomId, cancel: cancel), includeMedia: false),
        ];
      } on SeventeenLiveException catch (error) {
        if (error.kind == SeventeenLiveFailure.missing) return [];
        rethrow;
      }
    }
    final query = keyword.trim();
    if (query.isEmpty ||
        query.length > 100 ||
        Uri.tryParse(query)?.hasScheme == true)
      return [];
    final rooms = await _api.searchCurrentLive(query, cancel: cancel);
    return rooms
        .take(pageSize)
        .map((room) => _card(room, includeMedia: false))
        .toList(growable: false);
  }

  SeventeenLiveRoom _snapshot(LiveRoom detail) {
    final roomId = _roomId(detail.roomId ?? '', detail.platform ?? '');
    final data = detail.data;
    if (data is! SeventeenLiveRoom ||
        data.roomId != roomId ||
        data.userId != detail.userId) {
      throw const SeventeenLiveException(SeventeenLiveFailure.identity);
    }
    if (data.state == SeventeenLiveState.unknown) {
      throw const SeventeenLiveException(SeventeenLiveFailure.unknownState);
    }
    if (data.state != SeventeenLiveState.live ||
        detail.isExplicitlyOfflineNow) {
      throw const SeventeenLiveException(SeventeenLiveFailure.mediaUnavailable);
    }
    if (data.streams.isEmpty)
      throw const SeventeenLiveException(SeventeenLiveFailure.mediaUnavailable);
    return data;
  }

  static String _qualityName(String qualityId) => switch (qualityId) {
    'enhanced' => i18n('seventeen_quality_enhanced'),
    'hd' => i18n('seventeen_quality_hd'),
    'h264' => i18n('seventeen_quality_h264'),
    'standard' => i18n('seventeen_quality_standard'),
    _ => throw const SeventeenLiveException(SeventeenLiveFailure.schema),
  };

  static int _qualitySort(String qualityId) => switch (qualityId) {
    'enhanced' => 400,
    'hd' => 300,
    'h264' => 200,
    'standard' => 100,
    _ => 0,
  };

  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoom detail,
  }) async {
    if (detail.isExplicitlyOfflineNow) return [];
    final room = _snapshot(detail);
    return List.unmodifiable(
      room.streams.map(
        (stream) => LivePlayQuality(
          id: stream.qualityId,
          quality: '${_qualityName(stream.qualityId)} · FLV',
          sort: _qualitySort(stream.qualityId),
        ),
      ),
    );
  }

  Future<LivePlayUrlResolution> _resolve(
    LiveRoom detail,
    LivePlayQuality quality, {
    required bool refresh,
  }) async {
    var room = _snapshot(detail);
    if (refresh)
      room = _snapshot(await getRoomDetail(roomId: room.roomId, platform: id));
    final qualityId = quality.selectionId.toString();
    for (final stream in room.streams) {
      if (stream.qualityId == qualityId) {
        return LivePlayUrlResolution(
          urls: List.unmodifiable(stream.urls.map((uri) => uri.toString())),
          appliedQualityData: qualityId,
        );
      }
    }
    throw const SeventeenLiveException(SeventeenLiveFailure.mediaUnavailable);
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality, refresh: false);

  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality, refresh: true);

  Future<List<String>> getPlayUrls({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => (await _resolve(detail, quality, refresh: false)).urls;
}
