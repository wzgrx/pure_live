// Writes expected.json for the LiveMe samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.21-liveme.md, "v3 的冻结输出").
//
// The archive has no LiveMe expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below the models is
// 3.x's LiveMeApi, LiveMeLink, LiveMeSigner and LiveMeSite, copied from
// legacy/lib/core/site/liveme/liveme_api.dart, liveme_link.dart,
// liveme_signer.dart and liveme_site.dart (archive/v4). 3.x already injected
// its transport (`LiveMeRequest`), so only that function is replaced: it
// answers from the samples by method, host, path and query (the clock value
// `_time` left out), a POST also by its `videoid` form field (the signature
// fields change every run), like the legacy FixtureAdapter, with the empty
// body 3.x read for any status other than 200, and throws a StateError for a
// request without a sample (rethrown by `_json`, so a harness gap is never
// taken for 3.x's transport failure). The recorded requests write `<time>`
// for `_time`. Dio's CancelToken and DioException, 3.x's LiveRoom, LiveArea,
// LivePlayQuality, LivePlayUrlResolution, LiveDirectoryPage and
// HttpHeaderPolicy are reduced to the parts these classes use; `i18n`
// answers 3.x's zh.json. LiveMeSite keeps its method bodies; its
// `extends`/`implements` clause, the `@override`s and `getDanmaku`
// (EmptyDanmaku) are left out, and both constructors require the injected
// transport. The network path (`_defaultRequest`, `readBody`) is left out.
// The LiveMe branch of 3.x's LiveUrlTool._parseLiveUrl
// (live_url_tool.dart:223-228) is copied as `_legacyShareImport`. The output
// format is the legacy harness's (`roomProjection`, `errorProjection`,
// `{generator, value}`).
//
// Run from the repository root: dart run fixtures/liveme/legacy_expected.dart
// (package:crypto, 3.x's signer dependency, is in the workspace).
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

const _root = 'fixtures/liveme';
const _liveShortId = '209683072';
const _liveUserId = '932385543319330816';
const _liveVideoId = '17904580585651396476';
const _offlineShortId = '17709377';
const _offlineUserId = '560875115161059328';
const _shareUrl = 'https://www.liveme.com/us/m/v/$_liveVideoId/index.html?live=1';

void main() async {
  await _featured('S01-featurelist-p1', 1);
  await _featured('S01-featurelist-p2', 2);
  await _search('S02-search-p1', 'andre', 1);
  await _search('S02-search-p2', 'andre', 2);
  await _search('S02-search-empty', 'qzxqzxqzxpurelive', 1);
  await _room('S03-mapping-live', _liveShortId, ['S04-profile-live', 'S05-query-live']);
  await _room('S03-mapping-offline', _offlineShortId, ['S04-profile-offline']);
  await _room('S03-mapping-notfound', '999999999', const []);
  await _profileLink('S04-profile-live', _liveUserId, ['S03-mapping-live', 'S05-query-live']);
  await _profileLink('S04-profile-offline', _offlineUserId, ['S03-mapping-offline']);
  await _profileLink('S04-profile-notfound', '1000000000000000001', const []);
  await _videoLink();
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final List<String> _requests = [];

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _replay(List<String> samples) {
  _samples = [for (final sample in samples) _meta(sample)];
  _requests.clear();
}

Map<String, String> _withoutClock(Map<String, String> query) => {
  for (final entry in query.entries)
    if (entry.key != '_time') entry.key: entry.value,
};

bool _sameQuery(Map<String, String> a, Map<String, String> b) {
  final left = _withoutClock(a);
  final right = _withoutClock(b);
  return left.length == right.length && left.entries.every((entry) => right[entry.key] == entry.value);
}

String _stable(Uri uri) {
  if (!uri.queryParameters.containsKey('_time')) return uri.toString();
  return uri.toString().replaceFirst(RegExp(r'_time=[0-9]+'), '_time=<time>');
}

/// 3.x's `LiveMeRequest` over the samples: 3.x read no body for a status
/// other than 200.
Future<({int status, String body})> _fixtureRequest({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  Map<String, String>? form,
  CancelToken? cancel,
}) async {
  _requests.add('$method ${_stable(uri)}${form == null ? '' : ' videoid=${form['videoid']}'}');
  for (final meta in _samples) {
    final request = meta['request'] as Map;
    final recorded = Uri.parse(request['url'] as String);
    if (request['method'] != method ||
        recorded.host != uri.host ||
        recorded.path != uri.path ||
        !_sameQuery(recorded.queryParameters, uri.queryParameters)) {
      continue;
    }
    if (form != null && Uri.splitQueryString(request['body'] as String)['videoid'] != form['videoid']) continue;
    final status = (meta['response'] as Map)['status'] as int;
    if (status != 200) return (status: status, body: '');
    return (status: 200, body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync());
  }
  throw StateError('No recorded sample for $method $uri');
}

LiveMeApi _api() => LiveMeApi(request: _fixtureRequest);

LiveMeSite _site() => LiveMeSite(api: _api());

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
    NoSuchMethodError() => 'NoSuchMethodError',
    _ => error.runtimeType.toString(),
  },
  'message': error.toString(),
};

Future<Object?> _outcome<T>(Future<T> Function() body, Object? Function(T value) project) async {
  try {
    return project(await body());
  } on Object catch (error) {
    if (error is StateError) rethrow;
    return _errorProjection(error);
  }
}

/// [body]'s outcome and the requests it sent.
Future<Map<String, Object?>> _counted<T>(Future<T> Function() body, Object? Function(T value) project) async {
  final before = _requests.length;
  final outcome = await _outcome(body, project);
  return {'value': outcome, 'requests': _requests.sublist(before)};
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

Object? _linkProjection(LiveMeLink? link) => link == null ? null : {'kind': link.kind.name, 'id': link.id};

/// The LiveMe branch of 3.x's `LiveUrlTool._parseLiveUrl`
/// (live_url_tool.dart:223-228) for one shared URL [raw].
Future<List<String>> _legacyShareImport(String raw, LiveMeApi liveMeApi) async {
  final cancel = CancelToken();
  final liveMe = LiveMeLink.parse(raw);
  if (liveMe != null) {
    final shortId = await liveMeApi.resolveReference(liveMe, cancel: cancel);
    if (cancel.isCancelled) return [];
    return [shortId, 'liveme'];
  }
  return [];
}

Map<String, Object?> _resolution(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
};

// Samples ---------------------------------------------------------------------

Future<void> _featured(String sample, int page) async {
  _replay([sample]);
  final site = _site();
  final value = <String, Object?>{
    'getDirectoryPage': await _counted(
      () => site.getDirectoryPage(page: page),
      (result) => {'rooms': _rooms(result.rooms), 'page': result.page, 'hasMore': result.hasMore},
    ),
    'getRecommendRooms': await _counted(() => site.getRecommendRooms(page: page, pageSize: 20), _rooms),
  };
  var generator = 'LiveMeSite.getDirectoryPage + getRecommendRooms (page size 20)';
  if (page == 1) {
    final area = LiveArea(platform: 'liveme', areaType: 'featured', areaId: 'featured', areaName: 'LiveMe');
    value['getDirectoryPage(category)'] = await _counted(() => site.getDirectoryPage(category: area), (_) => null);
    value['getRecommendRooms(page 0)'] = await _counted(() => site.getRecommendRooms(page: 0), _rooms);
    value['directoryNoticeKey'] = site.directoryNoticeKey;
    final card = (await site.getDirectoryPage(page: page)).rooms.first;
    value['getPlayQualites(card)'] = await _outcome(() => site.getPlayQualites(detail: card), (qualities) => qualities);
    generator +=
        ' + getDirectoryPage(category) + getRecommendRooms(page 0) + directoryNoticeKey'
        ' + getPlayQualites of the first card';
  }
  _write(sample, generator, value);
}

Future<void> _search(String sample, String keyword, int page) async {
  _replay([sample]);
  final site = _site();
  _write(sample, 'LiveMeSite.searchRooms (page size 30) + LiveMeApi.search hasMore', {
    'searchRooms': await _counted(() => site.searchRooms(keyword, page: page, pageSize: 30), _rooms),
    'LiveMeApi.search.hasMore': await _outcome(
      () => _api().search(keyword, page: page, pageSize: 30),
      (result) => result.hasMore,
    ),
  });
}

Future<void> _room(String sample, String shortId, List<String> more) async {
  _replay([sample, ...more]);
  final site = _site();
  final value = <String, Object?>{
    'getRoomDetailForRefresh': await _counted(
      () => site.getRoomDetailForRefresh(roomId: shortId, platform: 'liveme'),
      _roomProjection,
    ),
    'getRoomDetail': await _counted(() => site.getRoomDetail(roomId: shortId, platform: 'liveme'), _roomProjection),
    'getRoomDetailForRecording': await _counted(
      () => site.getRoomDetailForRecording(roomId: shortId, platform: 'liveme'),
      _roomProjection,
    ),
    'getLiveStatus': await _counted(() => site.getLiveStatus(roomId: shortId, platform: 'liveme'), (live) => live),
    'searchRooms(shortId)': await _counted(() => site.searchRooms(shortId), _rooms),
    'searchRooms(shortId, page 2)': await _counted(() => site.searchRooms(shortId, page: 2), _rooms),
    'searchRooms(link)': await _counted(
      () => site.searchRooms('https://www.liveme.com/us/livehot/streaming/$shortId'),
      _rooms,
    ),
  };
  final generator = StringBuffer(
    'LiveMeSite.getRoomDetailForRefresh / getRoomDetail / getRoomDetailForRecording / getLiveStatus / '
    'searchRooms($shortId, its page 2 and its room link)',
  );
  try {
    final detail = await site.getRoomDetail(roomId: shortId, platform: 'liveme');
    final qualities = await site.getPlayQualites(detail: detail);
    value['getPlayQualites'] = [
      for (final quality in qualities)
        {
          'quality': quality.quality,
          'id': quality.id,
          'sort': quality.sort,
          'getPlayUrls': await _outcome(() => site.getPlayUrls(detail: detail, quality: quality), (urls) => urls),
          'resolvePlayUrlsRaw': await _outcome(
            () => site.resolvePlayUrlsRaw(detail: detail, quality: quality),
            _resolution,
          ),
        },
    ];
    generator.write(' + getPlayQualites + getPlayUrls + resolvePlayUrlsRaw');
    final probe = LivePlayQuality(id: 'source-flv', quality: '原始画质 · FLV', sort: 300);
    value['getPlayUrls(source-flv)'] = await _outcome(
      () => site.getPlayUrls(detail: detail, quality: probe),
      (urls) => urls,
    );
    value['resolvePlayUrlsForRecoveryRaw(source-flv)'] = await _counted(
      () => site.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: probe),
      _resolution,
    );
    generator.write(' + getPlayUrls / resolvePlayUrlsForRecoveryRaw of source-flv');
  } on StateError {
    rethrow;
  } on Object catch (error) {
    value['getPlayQualites'] = _errorProjection(error);
    generator.write(' + getPlayQualites');
  }
  _write(sample, generator.toString(), value);
}

Future<void> _profileLink(String sample, String userId, List<String> more) async {
  _replay([sample, ...more]);
  final link = 'https://www.liveme.com/u/$userId';
  _write(sample, 'LiveUrlTool share import and LiveMeSite.searchRooms of $link', {
    'shareImport': await _counted(() => _legacyShareImport(link, _api()), (result) => result),
    'searchRooms(link)': await _counted(() => _site().searchRooms(link), _rooms),
  });
}

Future<void> _videoLink() async {
  const sample = 'S05-query-live';
  _replay([sample, 'S03-mapping-live', 'S04-profile-live']);
  final vectors = [
    'https://www.liveme.com/livehot/streaming/209683072',
    'https://liveme.com/us/livehot/streaming/209683072',
    'http://www.liveme.com/zh-tw/LiveHot/Streaming/209683072/',
    ' https://www.liveme.com/livehot/streaming/209683072?from=share#top ',
    'https://www.liveme.com:8443/livehot/streaming/209683072',
    'https://WWW.LIVEME.COM/livehot/streaming/209683072',
    'https://www.liveme.com/../livehot/streaming/209683072',
    'https://www.liveme.com/livehot/streaming/0209683072',
    'https://www.liveme.com/livehot/streaming/1234',
    'https://www.liveme.com/livehot/streaming/1234567890123',
    'https://www.liveme.com/livehot/streaming/209683072/extra',
    'https://www.liveme.com/xx-abcde/livehot/streaming/209683072',
    'https://m.liveme.com/livehot/streaming/209683072',
    'https://user@www.liveme.com/livehot/streaming/209683072',
    'ftp://www.liveme.com/livehot/streaming/209683072',
    'https://www.liveme.com/%FF/livehot/streaming/209683072',
    'https://www.liveme.com/u/$_liveUserId',
    'https://www.liveme.com/us/U/$_liveUserId',
    'https://www.liveme.com/u/123',
    'https://www.liveme.com/v/$_liveVideoId',
    _shareUrl,
    'https://www.liveme.com/m/v/$_liveVideoId/index.htm',
    'https://www.liveme.com/m/v/$_liveVideoId',
    '209683072',
    '12345',
    '1234',
    '123456789012',
    '1234567890123',
    '0209683072',
    'andre',
  ];
  Object? attempt(Object? Function() body) {
    try {
      return body();
    } on Object catch (error) {
      return _errorProjection(error);
    }
  }

  _write(
    sample,
    'LiveMeLink.parse / parseOrShortId of link vectors + LiveUrlTool share import and '
    'LiveMeSite.searchRooms of the share URL (shareurl) and the /v/ link',
    {
      'vectors': [
        for (final vector in vectors)
          {
            'input': vector,
            'parse': attempt(() => _linkProjection(LiveMeLink.parse(vector))),
            'parseOrShortId': attempt(() => _linkProjection(LiveMeLink.parseOrShortId(vector))),
          },
      ],
      'shareImport(shareurl)': await _counted(() => _legacyShareImport(_shareUrl, _api()), (result) => result),
      'shareImport(/v/)': await _counted(
        () => _legacyShareImport('https://www.liveme.com/v/$_liveVideoId', _api()),
        (result) => result,
      ),
      'searchRooms(shareurl)': await _counted(() => _site().searchRooms(_shareUrl), _rooms),
    },
  );
}

// Dio and 3.x models (the parts the LiveMe classes use) ----------------------

class CancelToken {
  bool isCancelled = false;

  static bool isCancel(Object error) => false;
}

class DioException implements Exception {}

String i18n(String key) =>
    const {
      'liveme_chat_notice': 'LiveMe 远端聊天尚待接入；热度、当前观看和累计观看分别展示。',
      'liveme_quality_source': '原始画质',
      'liveme_quality_smooth': '流畅画质',
      'liveme_quality_hls': 'HLS 自动',
    }[key] ??
    key;

/// 3.x's `HttpHeaderPolicy.normalize` (core/common/http_header_policy.dart).
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

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

class LiveArea {
  LiveArea({this.platform, this.areaType, this.typeName, this.areaId, this.areaName, this.areaPic, this.shortName});

  String? platform = '';
  String? areaType = '';
  String? typeName = '';
  String? areaId = '';
  String? areaName = '';
  String? areaPic = '';
  String? shortName = '';
}

class LivePlayQuality {
  LivePlayQuality({required this.quality, this.data, this.id, this.sort = 0});

  final String quality;
  final dynamic data;
  final Object? id;
  final int sort;

  Object get selectionId => id ?? quality;

  Map<String, Object?> toJson() => {'quality': quality, 'id': id, 'sort': sort};
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
    'httpHeaders': HttpHeaderPolicy.normalize(httpHeaders),
  };
}

// 3.x's liveme_api.dart ------------------------------------------------------

enum LiveMeFailure {
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

class LiveMeException implements Exception {
  const LiveMeException(this.kind);

  final LiveMeFailure kind;

  @override
  String toString() => 'LiveMe ${kind.name}';
}

enum LiveMeState { live, offline, restricted, unknown }

class LiveMeStream {
  LiveMeStream({required this.qualityId, required this.protocol, required Iterable<Uri> urls})
    : urls = List.unmodifiable(urls);

  final String qualityId;
  final String protocol;
  final List<Uri> urls;
}

class LiveMeRoom {
  LiveMeRoom({
    required this.shortId,
    required this.userId,
    required this.videoId,
    required this.nickname,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.bio,
    required this.countryCode,
    required this.followers,
    required this.currentViewers,
    required this.totalViewers,
    required this.heat,
    required this.likes,
    required this.state,
    required Iterable<LiveMeStream> streams,
  }) : streams = List.unmodifiable(streams);

  final String shortId;
  final String userId;
  final String videoId;
  final String nickname;
  final String title;
  final String avatar;
  final String cover;
  final String bio;
  final String countryCode;
  final int? followers;
  final int? currentViewers;
  final int? totalViewers;
  final int? heat;
  final int? likes;
  final LiveMeState state;
  final List<LiveMeStream> streams;
}

class LiveMeDirectoryPage {
  LiveMeDirectoryPage({required Iterable<LiveMeRoom> rooms, required this.hasMore}) : rooms = List.unmodifiable(rooms);

  final List<LiveMeRoom> rooms;
  final bool hasMore;
}

class LiveMeSearchPage {
  LiveMeSearchPage({required Iterable<LiveMeRoom> rooms, required this.hasMore}) : rooms = List.unmodifiable(rooms);

  final List<LiveMeRoom> rooms;
  final bool hasMore;
}

typedef LiveMeRequest = Future<({int status, String body})> Function({
  required String method,
  required Uri uri,
  required Map<String, String> headers,
  Map<String, String>? form,
  CancelToken? cancel,
});

class LiveMeApi {
  LiveMeApi({required LiveMeRequest request, LiveMeSigner? signer})
    : _request = request,
      _signer = signer ?? LiveMeSigner();

  static const origin = 'https://www.liveme.com';
  static const apiOrigin = 'https://live.liveme.com';
  static const directoryOrigin = 'https://lvapi.liveme.com';
  static const responseLimit = 8 * 1024 * 1024;
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  final LiveMeRequest _request;
  final LiveMeSigner _signer;

  static Map<String, String> requestHeaders({String? shortId}) => {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Origin': origin,
    'Referer': shortId == null ? '$origin/livehot' : LiveMeLink.url(shortId),
  };

  static Map<String, String> mediaHeaders(String shortId) => {
    'User-Agent': userAgent,
    'Origin': origin,
    'Referer': LiveMeLink.url(shortId),
  };

  Future<Map<String, dynamic>> _json({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    Map<String, String>? form,
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled == true) throw const LiveMeException(LiveMeFailure.cancelled);
    late final ({int status, String body}) response;
    try {
      response = await _request(method: method, uri: uri, headers: headers, form: form, cancel: cancel);
    } catch (error) {
      if (cancel?.isCancelled == true || (error is DioException && CancelToken.isCancel(error))) {
        throw const LiveMeException(LiveMeFailure.cancelled);
      }
      if (error is LiveMeException) rethrow;
      // The harness has no network: a request without a sample is a harness
      // error, not 3.x's transport failure.
      if (error is StateError) rethrow;
      throw const LiveMeException(LiveMeFailure.transport);
    }
    if (cancel?.isCancelled == true) throw const LiveMeException(LiveMeFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      400 => LiveMeFailure.schema,
      401 || 403 => LiveMeFailure.access,
      404 => LiveMeFailure.missing,
      420 || 429 => LiveMeFailure.rateLimited,
      >= 500 => LiveMeFailure.service,
      _ => LiveMeFailure.transport,
    };
    if (failure != null) throw LiveMeException(failure);
    if (response.body.length > responseLimit) throw const LiveMeException(LiveMeFailure.schema);
    try {
      final root = _object(jsonDecode(response.body));
      final apiStatus = _integer(root['status']);
      if (apiStatus == null) throw const LiveMeException(LiveMeFailure.schema);
      if (apiStatus == 200) return root;
      throw LiveMeException(switch (apiStatus) {
        400 || 404 => LiveMeFailure.missing,
        401 || 403 => LiveMeFailure.access,
        420 || 429 => LiveMeFailure.rateLimited,
        >= 500 => LiveMeFailure.service,
        _ => LiveMeFailure.schema,
      });
    } on FormatException {
      throw const LiveMeException(LiveMeFailure.schema);
    }
  }

  Map<String, String> _guestQuery({bool includeTime = true}) => {
    'alias': 'liveme',
    'tongdun_black_box': '1',
    'os': 'web',
    if (includeTime) '_time': '${DateTime.now().millisecondsSinceEpoch}',
    'h5': '1',
    'thirdchannel': '6',
  };

  Future<LiveMeDirectoryPage> directory({int page = 1, int pageSize = 20, CancelToken? cancel}) async {
    if (page < 1 || pageSize < 1 || pageSize > 50) {
      throw const LiveMeException(LiveMeFailure.schema);
    }
    final root = await _json(
      method: 'GET',
      uri: Uri.parse('$directoryOrigin/live/featurelist').replace(
        queryParameters: {
          'countryCode': 'GLOBAL',
          'page_index': '$page',
          'page_size': '$pageSize',
          'pid': '3',
          'posid': '3002',
          'h5': '1',
        },
      ),
      headers: requestHeaders(),
      cancel: cancel,
    );
    final data = _object(root['data']);
    final rooms = <LiveMeRoom>[];
    final seen = <String>{};
    for (final raw in _list(data['video_info'], max: 100)) {
      final video = _object(raw);
      // Some featured cards (e.g. union rooms) carry no short id. Rooms are
      // keyed by short id, so such a card cannot be opened or followed; skip
      // it instead of failing the whole page. Present-but-invalid ids still
      // fail below.
      if (video['ushortid'] == null) continue;
      final room = _videoRoom(video, includeMedia: false);
      if (room.state != LiveMeState.restricted && seen.add(room.shortId)) rooms.add(room);
    }
    return LiveMeDirectoryPage(rooms: rooms, hasMore: _integer(data['next_page']) == 1);
  }

  Future<LiveMeSearchPage> search(String keyword, {int page = 1, int pageSize = 30, CancelToken? cancel}) async {
    final query = keyword.trim();
    if (query.isEmpty || query.length > 256 || page < 1 || pageSize < 1 || pageSize > 40) {
      throw const LiveMeException(LiveMeFailure.schema);
    }
    final root = await _json(
      method: 'GET',
      uri: Uri.parse('$apiOrigin/search/searchKeyword').replace(
        queryParameters: {
          ..._guestQuery(),
          'type': '1',
          'page': '$page',
          'pageSize': '$pageSize',
          'keyword': query,
          'tuid': '',
          'uid': '',
          'token': '',
          'androidid': '',
        },
      ),
      headers: requestHeaders(),
      cancel: cancel,
    );
    final data = _object(root['data']);
    final rows = _list(data['data_info'], max: 100);
    final rooms = <LiveMeRoom>[];
    final seen = <String>{};
    for (final raw in rows) {
      final row = _object(raw);
      final shortId = _shortId(row['short_id']);
      if (!seen.add(shortId)) continue;
      final nickname = _firstText([row['nickname'], row['uname']]);
      final project = _optionalText(row['project']).toLowerCase();
      final isLive = _integer(row['is_live']);
      rooms.add(
        LiveMeRoom(
          shortId: shortId,
          userId: _longId(row['user_id']),
          videoId: '',
          nickname: nickname,
          title: nickname,
          avatar: _image(row['face']),
          cover: '',
          bio: '',
          countryCode: _country(row['countryCode']),
          followers: _optionalNonNegativeInt(row['fans_num'] ?? row['follower_count']),
          currentViewers: null,
          totalViewers: null,
          heat: null,
          likes: null,
          // The federated emolm/alive/highlive projects may report is_live=0
          // while their public LiveMe room is active. Keep those rows pending
          // until room lookup; the primary liveme project has reliable zeros.
          state: isLive == 1
              ? LiveMeState.live
              : isLive == 0 && project == 'liveme'
              ? LiveMeState.offline
              : LiveMeState.unknown,
          streams: const [],
        ),
      );
    }
    return LiveMeSearchPage(rooms: rooms, hasMore: rows.length >= pageSize);
  }

  Future<String> resolveReference(LiveMeLink reference, {CancelToken? cancel}) async {
    switch (reference.kind) {
      case LiveMeLinkKind.shortId:
        return _shortId(reference.id);
      case LiveMeLinkKind.userId:
        return (await _profile(reference.id, cancel: cancel)).shortId;
      case LiveMeLinkKind.videoId:
        return (await _video(reference.id, includeMedia: false, cancel: cancel)).shortId;
    }
  }

  Future<LiveMeRoom> room(String rawShortId, {required bool includeMedia, CancelToken? cancel}) async {
    final shortId = LiveMeLink.normalizeShortId(rawShortId);
    if (shortId == null) throw const LiveMeException(LiveMeFailure.identity);
    final mapping = await _mapping(shortId, cancel: cancel);
    final profileFuture = _profile(mapping.userId, cancel: cancel);
    if (mapping.videoId.isEmpty) {
      return _offlineRoom(await profileFuture, expectedShortId: shortId);
    }
    final results = await Future.wait<Object>([
      profileFuture,
      _video(mapping.videoId, expectedShortId: shortId, includeMedia: includeMedia, cancel: cancel),
    ]);
    final profile = results[0] as _LiveMeProfile;
    final video = results[1] as LiveMeRoom;
    if (profile.shortId != shortId || profile.userId != mapping.userId || video.userId != mapping.userId) {
      throw const LiveMeException(LiveMeFailure.identity);
    }
    return _mergeProfile(video, profile);
  }

  Future<({String userId, String videoId})> _mapping(String shortId, {CancelToken? cancel}) async {
    final root = await _json(
      method: 'GET',
      uri: Uri.parse('$apiOrigin/liveme_ent/v1/user/uid_vid_by_short_id')
          .replace(queryParameters: {..._guestQuery(), 'short_id': shortId}),
      headers: requestHeaders(shortId: shortId),
      cancel: cancel,
    );
    final data = _object(root['data']);
    final userId = _longId(data['uid']);
    final rawVideoId = _optionalText(data['vid']);
    final videoId = rawVideoId.isEmpty ? '' : _longId(rawVideoId);
    return (userId: userId, videoId: videoId);
  }

  Future<_LiveMeProfile> _profile(String rawUserId, {CancelToken? cancel}) async {
    final userId = _longId(rawUserId);
    final root = await _json(
      method: 'GET',
      uri: Uri.parse('$apiOrigin/user/getinfo').replace(queryParameters: {..._guestQuery(), 'userid': userId}),
      headers: requestHeaders(),
      cancel: cancel,
    );
    final user = _object(_object(root['data'])['user']);
    final info = _object(user['user_info']);
    final actualUserId = _longId(info['uid'] ?? info['userid'] ?? info['cm_openid']);
    if (actualUserId != userId) throw const LiveMeException(LiveMeFailure.identity);
    final counts = _object(user['count_info']);
    return _LiveMeProfile(
      shortId: _shortId(info['short_id']),
      userId: actualUserId,
      nickname: _firstText([info['nickname'], info['uname']]),
      avatar: _image(info['big_face'] ?? info['face']),
      cover: _image(info['big_cover'] ?? info['cover']),
      bio: _optionalText(info['usign']),
      countryCode: _country(info['countryCode']),
      followers: _optionalNonNegativeInt(counts['follower_count']),
    );
  }

  Future<LiveMeRoom> _video(
    String rawVideoId, {
    String? expectedShortId,
    required bool includeMedia,
    CancelToken? cancel,
  }) async {
    final videoId = _longId(rawVideoId);
    final query = <String, String>{'alias': 'liveme', 'tongdun_black_box': '1', 'os': 'web'};
    final signed = _signer.sign(
      query: query,
      body: {
        '_time': '${DateTime.now().millisecondsSinceEpoch}',
        'thirdchannel': '6',
        'videoid': videoId,
        'area': 'en',
        'vali': _signer.vali(),
      },
    );
    final root = await _json(
      method: 'POST',
      uri: Uri.parse('$apiOrigin/live/queryinfosimple').replace(queryParameters: query),
      headers: {
        ...requestHeaders(shortId: expectedShortId),
        'lm-s-sign': signed.signature,
      },
      form: signed.fields,
      cancel: cancel,
    );
    final data = _object(root['data']);
    final room = _videoRoom(
      _object(data['video_info']),
      user: data['user_info'] is Map ? _object(data['user_info']) : const {},
      includeMedia: includeMedia,
      expectedShortId: expectedShortId,
      expectedVideoId: videoId,
    );
    return room;
  }

  static LiveMeRoom _videoRoom(
    Map<String, dynamic> video, {
    Map<String, dynamic> user = const {},
    bool includeMedia = false,
    String? expectedShortId,
    String? expectedVideoId,
  }) {
    final shortId = _shortId(video['ushortid'] ?? user['short_id']);
    final userId = _longId(video['userid'] ?? user['userid'] ?? user['uid']);
    final rawVideoId = _optionalText(video['vid'] ?? video['vdoid']);
    final videoId = rawVideoId.isEmpty ? '' : _longId(rawVideoId);
    if ((expectedShortId != null && shortId != expectedShortId) ||
        (expectedVideoId != null && videoId != expectedVideoId)) {
      throw const LiveMeException(LiveMeFailure.identity);
    }
    final restricted =
        _integer(video['ispvt']) == 1 ||
        _integer(video['livebptype']) == 7 ||
        _optionalText(video['hot_label_v2'] is Map ? _object(video['hot_label_v2'])['text'] : null).toLowerCase() ==
            'paid broadcast';
    final online = _integer(video['online']);
    final status = _integer(video['status']);
    final roomState = _integer(video['roomstate']);
    final state = restricted
        ? LiveMeState.restricted
        : online == 1 && status == 0 && roomState == 0
        ? LiveMeState.live
        : online == 0 || (status != null && status != 0) || (roomState != null && roomState != 0)
        ? LiveMeState.offline
        : LiveMeState.unknown;
    final nickname = _firstText([video['uname'], user['uname'], user['nickname']]);
    final title = _optionalText(video['title']);
    return LiveMeRoom(
      shortId: shortId,
      userId: userId,
      videoId: videoId,
      nickname: nickname,
      title: title.isEmpty ? nickname : title,
      avatar: _image(video['uface'] ?? user['face']),
      cover: _image(video['videocapture'] ?? video['smallcover']),
      bio: _optionalText(user['desc'] ?? user['usign']),
      countryCode: _country(video['countryCode'] ?? video['country_code'] ?? user['countryCode']),
      followers: null,
      currentViewers: state == LiveMeState.live ? _optionalNonNegativeInt(video['playnumber']) : null,
      totalViewers: state == LiveMeState.live ? _optionalNonNegativeInt(video['watchnumber']) : null,
      heat: state == LiveMeState.live ? _optionalNonNegativeInt(video['heat']) : null,
      likes: _optionalNonNegativeInt(video['likenum']),
      state: state,
      streams: state == LiveMeState.live && includeMedia ? _streams(video) : const [],
    );
  }

  static LiveMeRoom _offlineRoom(_LiveMeProfile profile, {required String expectedShortId}) {
    if (profile.shortId != expectedShortId) throw const LiveMeException(LiveMeFailure.identity);
    return LiveMeRoom(
      shortId: profile.shortId,
      userId: profile.userId,
      videoId: '',
      nickname: profile.nickname,
      title: profile.nickname,
      avatar: profile.avatar,
      cover: profile.cover,
      bio: profile.bio,
      countryCode: profile.countryCode,
      followers: profile.followers,
      currentViewers: null,
      totalViewers: null,
      heat: null,
      likes: null,
      state: LiveMeState.offline,
      streams: const [],
    );
  }

  static LiveMeRoom _mergeProfile(LiveMeRoom room, _LiveMeProfile profile) => LiveMeRoom(
    shortId: room.shortId,
    userId: room.userId,
    videoId: room.videoId,
    nickname: room.nickname,
    title: room.title,
    avatar: room.avatar.isEmpty ? profile.avatar : room.avatar,
    cover: room.cover.isEmpty ? profile.cover : room.cover,
    bio: room.bio.isEmpty ? profile.bio : room.bio,
    countryCode: room.countryCode.isEmpty ? profile.countryCode : room.countryCode,
    followers: profile.followers,
    currentViewers: room.currentViewers,
    totalViewers: room.totalViewers,
    heat: room.heat,
    likes: room.likes,
    state: room.state,
    streams: room.streams,
  );

  static List<LiveMeStream> _streams(Map<String, dynamic> video) {
    final result = <LiveMeStream>[];
    void add(String qualityId, String protocol, Iterable<Object?> values) {
      final urls = <Uri>[];
      final seen = <Uri>{};
      for (final value in values) {
        for (final raw in _flattenUrls(value)) {
          final uri = _mediaUri(raw, protocol);
          if (uri != null && seen.add(uri)) urls.add(uri);
        }
      }
      if (urls.isNotEmpty) result.add(LiveMeStream(qualityId: qualityId, protocol: protocol, urls: urls));
    }

    add('source-flv', 'flv', [video['videosource'], video['videosourcemore']]);
    add('smooth-flv', 'flv', [video['smallsource'], video['smallsourcemore']]);
    add('hls', 'hls', [video['hlsvideosource']]);
    return List.unmodifiable(result);
  }

  static Iterable<String> _flattenUrls(Object? value, [int depth = 0]) sync* {
    if (depth > 3 || value == null) return;
    if (value is String) {
      final text = value.trim();
      if (text.startsWith('http://') || text.startsWith('https://')) {
        yield text;
        return;
      }
      if (text.length <= 131072 && (text.startsWith('[') || text.startsWith('{'))) {
        try {
          yield* _flattenUrls(jsonDecode(text), depth + 1);
        } on FormatException {
          return;
        }
      }
      return;
    }
    if (value is List && value.length <= 32) {
      for (final item in value) {
        yield* _flattenUrls(item, depth + 1);
      }
      return;
    }
    if (value is Map && value.length <= 32) {
      for (final item in value.values) {
        yield* _flattenUrls(item, depth + 1);
      }
    }
  }

  static Uri? _mediaUri(String raw, String protocol) {
    if (raw.isEmpty || raw.length > 65536 || raw.contains(RegExp(r'[\s\x00-\x1f]'))) return null;
    final uri = Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    final path = uri?.path.toLowerCase() ?? '';
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !_trustedMediaHost(host) ||
        (protocol == 'flv' ? !path.endsWith('.flv') : !path.endsWith('.m3u8'))) {
      return null;
    }
    return uri.replace(scheme: 'https');
  }

  static bool _trustedMediaHost(String host) =>
      host == 'linkv.fun' ||
      host.endsWith('.linkv.fun') ||
      host == 'emolm.com' ||
      host.endsWith('.emolm.com') ||
      host == 'liveme.com' ||
      host.endsWith('.liveme.com');

  static String _image(Object? value) {
    if (value is! String || value.isEmpty || value.length > 8192) return '';
    final uri = Uri.tryParse(value);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !(host == 'esxscloud.com' ||
            host.endsWith('.esxscloud.com') ||
            host == 'liveme.com' ||
            host.endsWith('.liveme.com') ||
            host == 'linkv.fun' ||
            host.endsWith('.linkv.fun'))) {
      return '';
    }
    return uri.replace(scheme: 'https').toString();
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const LiveMeException(LiveMeFailure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<dynamic> _list(Object? value, {required int max}) {
    if (value is! List || value.length > max) throw const LiveMeException(LiveMeFailure.schema);
    return value;
  }

  static int? _integer(Object? value) => value is int ? value : int.tryParse(value?.toString() ?? '');

  static int? _optionalNonNegativeInt(Object? value) {
    if (value == null || value == '') return null;
    final parsed = _integer(value);
    if (parsed == null || parsed < 0) throw const LiveMeException(LiveMeFailure.schema);
    return parsed;
  }

  static String _shortId(Object? value) {
    final result = LiveMeLink.normalizeShortId(value?.toString() ?? '');
    if (result == null) throw const LiveMeException(LiveMeFailure.identity);
    return result;
  }

  static String _longId(Object? value) {
    final result = LiveMeLink.normalizeLongId(value?.toString() ?? '');
    if (result == null) throw const LiveMeException(LiveMeFailure.identity);
    return result;
  }

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = _optionalText(value);
      if (text.isNotEmpty) return text;
    }
    throw const LiveMeException(LiveMeFailure.schema);
  }

  static String _optionalText(Object? value) {
    if (value == null) return '';
    if (value is! String || value.length > 131072) throw const LiveMeException(LiveMeFailure.schema);
    return value.trim();
  }

  static String _country(Object? value) {
    final text = _optionalText(value).toUpperCase();
    return RegExp(r'^[A-Z]{2}$').hasMatch(text) ? text : '';
  }
}

class _LiveMeProfile {
  const _LiveMeProfile({
    required this.shortId,
    required this.userId,
    required this.nickname,
    required this.avatar,
    required this.cover,
    required this.bio,
    required this.countryCode,
    required this.followers,
  });

  final String shortId;
  final String userId;
  final String nickname;
  final String avatar;
  final String cover;
  final String bio;
  final String countryCode;
  final int? followers;
}

// 3.x's liveme_link.dart -----------------------------------------------------

enum LiveMeLinkKind { shortId, userId, videoId }

class LiveMeLink {
  const LiveMeLink({required this.kind, required this.id});

  final LiveMeLinkKind kind;
  final String id;

  static LiveMeLink? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        !_officialHost(uri.host.toLowerCase())) {
      return null;
    }
    final segments = uri.pathSegments.where((value) => value.isNotEmpty).toList(growable: false);
    if (segments.isEmpty || segments.any((value) => value == '.' || value == '..')) return null;
    var offset = 0;
    if (_locale(segments.first)) offset = 1;
    final tail = segments.sublist(offset);
    if (tail.length == 3 && tail[0].toLowerCase() == 'livehot' && tail[1].toLowerCase() == 'streaming') {
      final id = normalizeShortId(tail[2]);
      return id == null ? null : LiveMeLink(kind: LiveMeLinkKind.shortId, id: id);
    }
    if (tail.length == 2 && tail[0].toLowerCase() == 'u') {
      final id = normalizeLongId(tail[1]);
      return id == null ? null : LiveMeLink(kind: LiveMeLinkKind.userId, id: id);
    }
    if (tail.length == 2 && tail[0].toLowerCase() == 'v') {
      final id = normalizeLongId(tail[1]);
      return id == null ? null : LiveMeLink(kind: LiveMeLinkKind.videoId, id: id);
    }
    if (tail.length == 4 &&
        tail[0].toLowerCase() == 'm' &&
        tail[1].toLowerCase() == 'v' &&
        tail[3].toLowerCase() == 'index.html') {
      final id = normalizeLongId(tail[2]);
      return id == null ? null : LiveMeLink(kind: LiveMeLinkKind.videoId, id: id);
    }
    return null;
  }

  static LiveMeLink? parseOrShortId(String raw) {
    final parsed = parse(raw);
    if (parsed != null) return parsed;
    final id = normalizeShortId(raw);
    return id == null ? null : LiveMeLink(kind: LiveMeLinkKind.shortId, id: id);
  }

  static String? parseDurableRoomId(String raw) {
    final reference = parse(raw);
    if (reference?.kind == LiveMeLinkKind.shortId) return reference!.id;
    return normalizeShortId(raw);
  }

  static String? normalizeShortId(String raw) {
    final value = raw.trim();
    return RegExp(r'^[1-9][0-9]{4,11}$').hasMatch(value) ? value : null;
  }

  static String? normalizeLongId(String raw) {
    final value = raw.trim();
    return RegExp(r'^[1-9][0-9]{12,23}$').hasMatch(value) ? value : null;
  }

  static String url(String raw) {
    final id = normalizeShortId(raw);
    if (id == null) throw const FormatException('Invalid LiveMe short ID');
    return 'https://www.liveme.com/livehot/streaming/$id';
  }

  static bool _officialHost(String host) => host == 'liveme.com' || host == 'www.liveme.com';

  static bool _locale(String value) => RegExp(r'^[a-z]{2}(?:-[a-z]{2,4})?$', caseSensitive: false).hasMatch(value);
}

// 3.x's liveme_signer.dart ---------------------------------------------------

class LiveMeSignedForm {
  const LiveMeSignedForm({required this.fields, required this.signature});

  final Map<String, String> fields;
  final String signature;
}

/// Reproduces the request signature emitted by LiveMe's current official web
/// client. The monotonic suffix keeps two requests in the same millisecond
/// distinct without depending on process-global mutable state.
class LiveMeSigner {
  LiveMeSigner({Random? random}) : _random = random ?? Random.secure();

  static const clientId = 'LM6000101139961122666757';
  static const _secret = 'dd46dbb442b6e4ba817d6347d2ddf493';
  static const _valiAlphabet = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  final Random _random;
  int _counter = 0;

  LiveMeSignedForm sign({required Map<String, String> query, required Map<String, String> body, DateTime? now}) {
    final timestamp = '${(now ?? DateTime.now()).millisecondsSinceEpoch}${_counter++ % 10000}';
    final fields = <String, String>{
      ...body,
      'lm_s_id': clientId,
      'lm_s_ts': timestamp,
      'lm_s_str': md5.convert(utf8.encode(timestamp)).toString(),
      'lm_s_ver': '1',
      'h5': '1',
    };
    final all = <String, String>{...query, ...fields};
    final keys = all.keys.toList(growable: false)..sort();
    final input = StringBuffer();
    for (final key in keys) {
      input
        ..write(key)
        ..write(all[key]);
    }
    input
      ..write(clientId)
      ..write(timestamp)
      ..write(_secret);
    return LiveMeSignedForm(
      fields: Map.unmodifiable(fields),
      signature: md5.convert(utf8.encode(input.toString())).toString(),
    );
  }

  String vali() => '${_randomText(4)}l${_randomText(4)}m${_randomText(5)}';

  String _randomText(int length) =>
      List.generate(length, (_) => _valiAlphabet[_random.nextInt(_valiAlphabet.length)], growable: false).join();
}

// 3.x's liveme_site.dart -----------------------------------------------------

class LiveMeSite {
  LiveMeSite({required LiveMeApi api}) : _api = api;

  final LiveMeApi _api;

  String get id => 'liveme';

  String get name => 'LiveMe';

  String get directoryNoticeKey => 'liveme_directory_scope';

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (category != null) throw const LiveMeException(LiveMeFailure.schema);
    final result = await _api.directory(page: page, cancel: cancel);
    return LiveDirectoryPage(
      page: page,
      hasMore: result.hasMore,
      rooms: result.rooms.map((room) => _card(room, includeMedia: false)),
    );
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    final result = await _api.directory(page: page, pageSize: pageSize.clamp(1, 50));
    return result.rooms.map((room) => _card(room, includeMedia: false)).toList(growable: false);
  }

  LiveRoom _card(LiveMeRoom room, {required bool includeMedia}) {
    final heat = room.heat?.toString();
    return LiveRoom(
      platform: id,
      roomId: room.shortId,
      userId: room.userId,
      nick: room.nickname,
      title: room.title,
      avatar: room.avatar,
      cover: room.cover,
      area: room.countryCode,
      followers: room.followers?.toString(),
      introduction: room.bio,
      link: LiveMeLink.url(room.shortId),
      liveStatus: switch (room.state) {
        LiveMeState.live => LiveStatus.live,
        LiveMeState.offline => LiveStatus.offline,
        LiveMeState.restricted => LiveStatus.banned,
        LiveMeState.unknown => LiveStatus.unknown,
      },
      watching: heat ?? '',
      popularity: heat ?? '',
      onlineViewers: room.currentViewers?.toString(),
      totalViewers: room.totalViewers?.toString(),
      audienceMetricType: heat == null ? AudienceMetricType.onlineViewers : AudienceMetricType.popularity,
      notice: i18n('liveme_chat_notice'),
      httpHeaders: LiveMeApi.mediaHeaders(room.shortId),
      data: includeMedia ? room : null,
    );
  }

  String _roomId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const LiveMeException(LiveMeFailure.identity);
    final normalized = LiveMeLink.normalizeShortId(roomId);
    if (normalized == null) throw const LiveMeException(LiveMeFailure.identity);
    return normalized;
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia}) async {
    final data = await _api.room(_roomId(roomId, platform), includeMedia: includeMedia);
    if (includeMedia && data.state == LiveMeState.live && data.streams.isEmpty) {
      throw const LiveMeException(LiveMeFailure.mediaUnavailable);
    }
    return _card(data, includeMedia: includeMedia);
  }

  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: true);

  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: true);

  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: false);

  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId, platform: platform);
    if (room.effectiveLiveStatus == LiveStatus.unknown) {
      throw const LiveMeException(LiveMeFailure.unknownState);
    }
    return room.isLiveNow;
  }

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final reference = LiveMeLink.parseOrShortId(keyword);
    if (reference != null) {
      if (page != 1) return [];
      try {
        final shortId = await _api.resolveReference(reference, cancel: cancel);
        return [_card(await _api.room(shortId, includeMedia: false, cancel: cancel), includeMedia: false)];
      } on LiveMeException catch (error) {
        if (error.kind == LiveMeFailure.missing) return [];
        rethrow;
      }
    }
    if (keyword.trim().isEmpty || page < 1 || pageSize < 1) return [];
    final result = await _api.search(keyword, page: page, pageSize: pageSize.clamp(1, 40), cancel: cancel);
    return result.rooms.map((room) => _card(room, includeMedia: false)).toList(growable: false);
  }

  LiveMeRoom _snapshot(LiveRoom detail) {
    final roomId = _roomId(detail.roomId ?? '', detail.platform ?? '');
    final data = detail.data;
    if (data is! LiveMeRoom || data.shortId != roomId || data.userId != detail.userId) {
      throw const LiveMeException(LiveMeFailure.identity);
    }
    if (data.state == LiveMeState.unknown) throw const LiveMeException(LiveMeFailure.unknownState);
    if (data.state != LiveMeState.live || detail.isExplicitlyOfflineNow || data.streams.isEmpty) {
      throw const LiveMeException(LiveMeFailure.mediaUnavailable);
    }
    return data;
  }

  static String _qualityName(LiveMeStream stream) => switch (stream.qualityId) {
    'source-flv' => i18n('liveme_quality_source'),
    'smooth-flv' => i18n('liveme_quality_smooth'),
    'hls' => i18n('liveme_quality_hls'),
    _ => throw const LiveMeException(LiveMeFailure.schema),
  };

  static int _qualitySort(String qualityId) => switch (qualityId) {
    'source-flv' => 300,
    'smooth-flv' => 200,
    'hls' => 100,
    _ => 0,
  };

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.isExplicitlyOfflineNow) return [];
    final room = _snapshot(detail);
    return List.unmodifiable(
      room.streams.map(
        (stream) => LivePlayQuality(
          id: stream.qualityId,
          quality: '${_qualityName(stream)} · ${stream.protocol.toUpperCase()}',
          sort: _qualitySort(stream.qualityId),
        ),
      ),
    );
  }

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality, {required bool refresh}) async {
    var room = _snapshot(detail);
    if (refresh) room = _snapshot(await getRoomDetail(roomId: room.shortId, platform: id));
    final qualityId = quality.selectionId.toString();
    for (final stream in room.streams) {
      if (stream.qualityId == qualityId) {
        return LivePlayUrlResolution(
          urls: List.unmodifiable(stream.urls.map((uri) => uri.toString())),
          appliedQualityData: qualityId,
        );
      }
    }
    throw const LiveMeException(LiveMeFailure.mediaUnavailable);
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) =>
      _resolve(detail, quality, refresh: false);

  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality, refresh: true);

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await _resolve(detail, quality, refresh: false)).urls;
}
