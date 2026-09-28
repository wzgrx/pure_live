// Writes expected.json for the Kugou Live samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.29-kugoulive.md, "v3 的冻结输出").
//
// The archive has no Kugou Live expected.json (its legacy harness only
// covered five platforms, and 3.x no longer builds). The code below is 3.x's
// KugouLiveApi, KugouLiveLink and KugouLiveSite, copied from
// legacy/lib/core/site/kugoulive/ (archive/v4). 3.x already injected its
// transport (`KugouLiveRequest`), so only that function is replaced: it
// answers from the samples by host, path and the query other than the clock
// values `_` (streamaddr) and `callback` (search), with the empty body 3.x
// read for any status other than 200 (all samples are 200). The search
// sample was recorded with `callback=pureLive1`; the server echoes whatever
// callback it is sent, so the harness answers with 3.x's own callback name
// in front of the recorded JSON. A request without a sample is a StateError;
// 3.x's `_scope` would turn it into `transport`, so it is also kept aside and
// rethrown after the call: a missing sample fails the run.
//
// The archive scrubbed the FLV `token` of S05-stream-live into another shape
// of digits, room id segment included (`0-7379016-…`). 3.x only accepts a
// token that starts with `0-<room id>-`; a live answer of 2026-09-28 has
// `0-5192416-…` for room 5192416. The copy in this repository restores that
// public segment (`0-3197156-…`); the rest of the token stays synthetic.
//
// `_defaultRequest` and `_readBody` (the network path) are left out, so
// `KugouLiveApi` needs its `request` and `KugouLiveSite` its `api`. Dio's
// CancelToken is reduced to the members 3.x used and 3.x's
// `withRequestCancellation` (core/common/request_scope.dart) is copied
// unchanged. `KugouLiveSite` keeps its method bodies without `extends`,
// `implements`, `@override` and `getDanmaku` (`EmptyDanmaku`). `i18n` returns
// 3.x's zh.json text. 3.x's LiveRoom, LiveArea, LiveCategory,
// LivePlayQuality, LivePlayUrlResolution and LiveDirectoryPage are reduced to
// the parts these classes use. The output format is the legacy harness's
// (`roomProjection`, `errorProjection`, `{generator, value}`); every traced
// entry also records the requests it made (URL with `_` and `callback`
// replaced by placeholders, and the headers).
//
// Run from the repository root: dart run fixtures/kugoulive/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint, unused_field, unused_element
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/kugoulive';

void main() async {
  await _home();
  await _recommend('S02-recommend-p1', 1);
  await _recommend('S02-recommend-p2', 2);
  await _areaPage();
  await _live();
  await _mobile();
  await _offline();
  await _notFound();
  await _streams();
  await _search();
  await _searchEmpty();
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final List<Map<String, Object?>> _requests = [];
String? _missingSample;

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

String _body(String sample) {
  final meta = _meta(sample);
  return File('$_root/$sample/${meta['body']}').readAsStringSync();
}

void _load(List<String> samples) {
  _samples = [for (final sample in samples) _meta(sample)];
  _requests.clear();
  _missingSample = null;
}

const _clockQuery = {'_', 'callback'};

Map<String, String> _without(Map<String, String> fields) => {
  for (final entry in fields.entries)
    if (!_clockQuery.contains(entry.key)) entry.key: entry.value,
};

bool _same(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

/// The request as recorded in expected.json: the clock values replaced.
Map<String, Object?> _describe(Uri uri, Map<String, String> headers) => {
  'url': uri
      .toString()
      .replaceFirstMapped(RegExp(r'([?&])_=\d+'), (match) => '${match[1]}_=<ms>')
      .replaceFirstMapped(RegExp(r'([?&])callback=pureLive\d+'), (match) => '${match[1]}callback=<callback>'),
  'headers': headers,
};

/// 3.x's `KugouLiveRequest` over the samples.
Future<({int status, String body})> _replay(Uri uri, Map<String, String> headers, CancelToken cancel) async {
  _requests.add(_describe(uri, headers));
  final meta = _samples.where((meta) {
    final request = meta['request'] as Map<String, dynamic>;
    if (request['method'] != 'GET') return false;
    final recorded = Uri.parse(request['url'] as String);
    return recorded.host == uri.host &&
        recorded.path == uri.path &&
        _same(_without(recorded.queryParameters), _without(uri.queryParameters));
  }).firstOrNull;
  if (meta == null) {
    _missingSample = 'No recorded sample for GET $uri';
    throw StateError(_missingSample!);
  }
  final status = (meta['response'] as Map<String, dynamic>)['status'] as int;
  if (status != 200) return (status: status, body: '');
  var body = File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync();
  final callback = uri.queryParameters['callback'];
  if (callback != null) body = body.replaceFirst(RegExp(r'^\s*pureLive1\('), '$callback(');
  return (status: 200, body: body);
}

KugouLiveApi _api() => KugouLiveApi(request: _replay);

KugouLiveSite _site() => KugouLiveSite(api: _api());

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

/// [body]'s projection with the requests it made.
Future<Object?> _outcome<T>(Future<T> Function() body, Object? Function(T value) project) async {
  final before = _requests.length;
  Object? value;
  try {
    value = project(await body());
  } on StateError {
    rethrow;
  } on Object catch (error) {
    value = _errorProjection(error);
  }
  final missing = _missingSample;
  if (missing != null) throw StateError(missing);
  return {
    'requests': [for (final request in _requests.skip(before)) request],
    'value': value,
  };
}

Object? _sync<T>(T Function() body, Object? Function(T value) project) {
  try {
    return project(body());
  } on StateError {
    rethrow;
  } on Object catch (error) {
    return _errorProjection(error);
  }
}

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere((key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty));
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

Map<String, dynamic> _pageProjection(LiveDirectoryPage page) => {
  'page': page.page,
  'hasMore': page.hasMore,
  'rooms': _rooms(page.rooms),
};

Map<String, dynamic> _qualityProjection(LivePlayQuality quality) => {
  'quality': quality.quality,
  'id': quality.id,
  'sort': quality.sort,
  'data': quality.data,
};

List<Map<String, dynamic>> _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities) _qualityProjection(quality),
];

Map<String, dynamic> _resolutionProjection(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
};

Object? _categories(List<LiveCategory> categories) => [
  for (final category in categories)
    {
      'id': category.id,
      'name': category.name,
      'children': [for (final area in category.children) area.toJson()],
    },
];

/// The variants 3.x kept on an entered room (its `KugouLiveRoom` in `data`).
Object? _variants(List<KugouLiveVariant> variants) => [
  for (final variant in variants)
    {
      'id': variant.id,
      'protocol': variant.protocol,
      'rate': variant.rate,
      'codec': variant.codec,
      'layout': variant.layout,
      'urls': [for (final url in variant.urls) url.toString()],
    },
];

LiveArea _area(String id, {String platform = 'kugoulive', String areaType = 'official'}) =>
    LiveArea(platform: platform, areaType: areaType, areaId: id, areaName: id, typeName: '酷狗直播');

// Samples ---------------------------------------------------------------------

/// The home page categories: 3.x's parser, the site's catalog (cached after
/// the first load) and the fixed fallback list.
Future<void> _home() async {
  _load(['S01-home']);
  final site = _site();
  final value = <String, Object?>{
    'parseCategoriesHtml': [
      for (final category in KugouLiveApi.parseCategoriesHtml(_body('S01-home')))
        {'id': category.id, 'name': category.name},
    ],
    'parseCategoriesHtml(no links)': [
      for (final category in KugouLiveApi.parseCategoriesHtml('<html><body>no categories</body></html>'))
        {'id': category.id, 'name': category.name},
    ],
    'getCategores(2, 1000)': await _outcome(() => site.getCategores(2, 1000), _categories),
    'getCategores(1, 0)': await _outcome(() => site.getCategores(1, 0), _categories),
    'getCategores(1, 1000)': await _outcome(() => site.getCategores(1, 1000), _categories),
    'getCategores(1, 1000) again': await _outcome(() => site.getCategores(1, 1000), _categories),
    'getCategores(1, 3)': await _outcome(() => site.getCategores(1, 3), _categories),
    'id': site.id,
    'name': site.name,
    'directoryNoticeKey': site.directoryNoticeKey,
  };
  _write(
    'S01-home',
    'KugouLiveApi.parseCategoriesHtml + KugouLiveSite.getCategores + id + name + directoryNoticeKey',
    value,
  );
}

/// A recommendation page by every entry 3.x had: the native page, the
/// recommended rooms and the 推荐 area (id 8000, the same endpoint).
Future<void> _recommend(String sample, int page) async {
  _load([sample]);
  final site = _site();
  final value = <String, Object?>{
    'getDirectoryPage($page)': await _outcome(() => site.getDirectoryPage(page: page), _pageProjection),
    'getRecommendRooms($page, 30)': await _outcome(() => site.getRecommendRooms(page: page, pageSize: 30), _rooms),
    'getCategoryRooms(8000, $page)': await _outcome(
      () => site.getCategoryRooms(_area('8000'), page: page, pageSize: 100),
      _rooms,
    ),
  };
  if (page == 1) {
    value['getDirectoryPage(0)'] = await _outcome(() => site.getDirectoryPage(page: 0), _pageProjection);
    value['getRecommendRooms(0)'] = await _outcome(() => site.getRecommendRooms(page: 0), _rooms);
    value['getRecommendRooms(1, 0)'] = await _outcome(() => site.getRecommendRooms(page: 1, pageSize: 0), _rooms);
    final first = (await site.getDirectoryPage(page: 1)).rooms.first;
    value['getPlayQualites(card)'] = await _outcome(() => site.getPlayQualites(detail: first), _qualities);
  }
  _write(
    sample,
    'KugouLiveSite.getDirectoryPage + getRecommendRooms + getCategoryRooms(推荐 8000)',
    value,
  );
}

/// The dance area (7024, `list_v4` with `star` rows) and the areas 3.x
/// refused before a request.
Future<void> _areaPage() async {
  _load(['S03-area-7024-p1', 'S01-home']);
  final site = _site();
  final value = <String, Object?>{
    'getDirectoryPage(1, 7024)': await _outcome(
      () => site.getDirectoryPage(page: 1, category: _area('7024')),
      _pageProjection,
    ),
    'getCategoryRooms(7024, 1, 3)': await _outcome(
      () => site.getCategoryRooms(_area('7024'), page: 1, pageSize: 3),
      _rooms,
    ),
    'getDirectoryPage(1, other platform)': await _outcome(
      () => site.getDirectoryPage(page: 1, category: _area('7024', platform: 'huya')),
      _pageProjection,
    ),
    'getDirectoryPage(1, other area type)': await _outcome(
      () => site.getDirectoryPage(page: 1, category: _area('7024', areaType: 'custom')),
      _pageProjection,
    ),
    'getDirectoryPage(1, 100003 before the catalog)': await _outcome(
      () => site.getDirectoryPage(page: 1, category: _area('100003')),
      _pageProjection,
    ),
  };
  await site.getCategores(1, 1000);
  value['getDirectoryPage(1, 100003 after the catalog)'] = await _outcome(
    () => site.getDirectoryPage(page: 1, category: _area('100003')),
    _pageProjection,
  );
  _write(
    'S03-area-7024-p1',
    'KugouLiveSite.getDirectoryPage(category) + getCategoryRooms (with S01-home for the catalog)',
    value,
  );
}

/// Every entry 3.x had for one room: room entry, follow refresh, recording
/// detail, state; with [streams], the entered room's variants, qualities,
/// URLs, resolution with lease times, and recovery.
Future<Map<String, Object?>> _roomEntries(KugouLiveSite site, String id, {bool streams = true}) async {
  final value = <String, Object?>{
    'getRoomDetailForRefresh': await _outcome(
      () => site.getRoomDetailForRefresh(roomId: id, platform: 'kugoulive'),
      _roomProjection,
    ),
    'getLiveStatus': await _outcome(() => site.getLiveStatus(roomId: id, platform: 'kugoulive'), (live) => live),
  };
  if (!streams) return value;
  value['getRoomDetail'] = await _outcome(
    () => site.getRoomDetail(roomId: id, platform: 'kugoulive'),
    _roomProjection,
  );
  value['getRoomDetailForRecording'] = await _outcome(
    () => site.getRoomDetailForRecording(roomId: id, platform: 'kugoulive'),
    _roomProjection,
  );
  final detail = await site.getRoomDetail(roomId: id, platform: 'kugoulive');
  final data = detail.data;
  value['data.variants'] = data is KugouLiveRoom ? _variants(data.variants) : null;
  value['getPlayQualites'] = await _outcome(() => site.getPlayQualites(detail: detail), _qualities);
  List<LivePlayQuality> qualities;
  try {
    qualities = await site.getPlayQualites(detail: detail);
  } on StateError {
    rethrow;
  } on Object {
    qualities = const [];
  }
  final now = DateTime.utc(2026, 9, 27, 18);
  value['resolvePlayUrlsRaw'] = {
    for (final quality in qualities)
      '${quality.id}': await _outcome(
        () => site.resolvePlayUrlsRaw(detail: detail, quality: quality),
        (resolution) => {
          ..._resolutionProjection(resolution),
          'invalidAt': [
            for (final url in resolution.urls) site.getPlayUrlInvalidAt(url, now: now)?.toUtc().toIso8601String(),
          ],
          'refreshAt': [
            for (final url in resolution.urls) site.getPlayUrlRefreshAt(url, now: now)?.toUtc().toIso8601String(),
          ],
        },
      ),
  };
  value['getPlayUrls'] = {
    for (final quality in qualities)
      '${quality.id}': await _outcome(() => site.getPlayUrls(detail: detail, quality: quality), (urls) => urls),
  };
  final probe = qualities.isNotEmpty ? qualities.first : LivePlayQuality(quality: 'FLV 码率档 4', id: 'flv:4:1:2');
  value['resolvePlayUrlsRaw(hls:4:1:2)'] = await _outcome(
    () => site.resolvePlayUrlsRaw(
      detail: detail,
      quality: LivePlayQuality(quality: 'HLS 码率档 4', id: 'hls:4:1:2'),
    ),
    _resolutionProjection,
  );
  value['resolvePlayUrlsForRecoveryRaw(${probe.id})'] = await _outcome(
    () => site.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: probe),
    _resolutionProjection,
  );
  final refreshed = await site.getRoomDetailForRefresh(roomId: id, platform: 'kugoulive');
  value['getPlayQualites(refreshed room)'] = await _outcome(
    () => site.getPlayQualites(detail: refreshed),
    _qualities,
  );
  return value;
}

Future<Object?> _searches(KugouLiveSite site, List<String> keywords) async => {
  for (final keyword in keywords)
    keyword: await _outcome(
      () => site.searchRoomsCancellable(keyword, page: 1, pageSize: 30, cancel: CancelToken()),
      _rooms,
    ),
};

/// 3.x's link rule over the forms a user may paste or search.
const _linkVectors = [
  '3197156',
  ' 3197156 ',
  '999',
  '12',
  '012345',
  '123456789012',
  'https://fanxing.kugou.com/3197156',
  'http://fanxing.kugou.com/3197156',
  'HTTPS://FANXING.KUGOU.COM/3197156',
  'https://fanxing.kugou.com/3197156?refer=2177',
  'https://fanxing.kugou.com/3197156/',
  'https://fanxing.kugou.com//3197156',
  'https://fanxing.kugou.com:443/3197156',
  'http://fanxing.kugou.com:80/3197156',
  'https://fanxing.kugou.com:8443/3197156',
  'https://mfanxing.kugou.com/3197156',
  'https://mfanxing.kugou.com/?roomId=3197156',
  'https://mfanxing.kugou.com?roomId=3197156',
  'https://mfanxing.kugou.com/share?roomId=3197156',
  'https://mfanxing.kugou.com/?roomId=12',
  'https://fanxing2.kugou.com/3197156',
  'https://fanxing.kugou.com/3197156#chat',
  'https://fanxing.kugou.com/3197156#',
  'https://user@fanxing.kugou.com/3197156',
  'https://fanxing.kugou.com.evil.test/3197156',
  'https://fanxing.kugou.com/pcindex/category/7024',
  'https://fanxing.kugou.com/channel/3197156',
  'ftp://fanxing.kugou.com/3197156',
  'fanxing.kugou.com/3197156',
  '酷狗 https://fanxing.kugou.com/3197156',
  '',
];

/// The live room (with its stream answer): every entry, the exact searches,
/// the identity checks, the link rules, the media headers and URL checks,
/// and the lease times.
Future<void> _live() async {
  _load(['S04-room-live', 'S05-stream-live']);
  final site = _site();
  final value = await _roomEntries(site, '3197156');
  value['getRoomDetail(link)'] = await _outcome(
    () => site.getRoomDetail(roomId: 'https://fanxing.kugou.com/3197156', platform: 'kugoulive'),
    _roomProjection,
  );
  value['getRoomDetail(other platform)'] = await _outcome(
    () => site.getRoomDetail(roomId: '3197156', platform: 'huya'),
    _roomProjection,
  );
  value['getRoomDetail(bad id)'] = await _outcome(
    () => site.getRoomDetail(roomId: '12', platform: 'kugoulive'),
    _roomProjection,
  );
  value['getPlayQualites(live card without data)'] = await _outcome(
    () => site.getPlayQualites(
      detail: LiveRoom(platform: 'kugoulive', roomId: '3197156', liveStatus: LiveStatus.live),
    ),
    _qualities,
  );
  value['getPlayQualites(offline card)'] = await _outcome(
    () => site.getPlayQualites(
      detail: LiveRoom(platform: 'kugoulive', roomId: '3197156', liveStatus: LiveStatus.offline),
    ),
    _qualities,
  );
  value['searchRooms'] = await _searches(site, [
    '3197156',
    ' 3197156 ',
    'https://fanxing.kugou.com/3197156',
    'https://mfanxing.kugou.com/?roomId=3197156',
  ]);
  value['searchRooms(3197156, page 2)'] = await _outcome(() => site.searchRooms('3197156', page: 2), _rooms);
  value['KugouLiveLink.parseRoomId'] = {
    for (final text in _linkVectors) text: _sync(() => KugouLiveLink.parseRoomId(text), (id) => id),
  };
  value['KugouLiveLink.watchUrl'] = {
    for (final text in ['3197156', ' 3197156 ', '12'])
      text: _sync(() => KugouLiveLink.watchUrl(text), (url) => url),
  };
  value['KugouLiveApi.mediaHeaders'] = KugouLiveApi.mediaHeaders('3197156');
  final flv = (((jsonDecode(_body('S05-stream-live')) as Map)['data'] as Map)['lines'] as List).first as Map;
  final signed = ((flv['streamProfiles'] as List).first as Map)['httpsFlv'] as List;
  final url = signed.first as String;
  value['KugouLiveApi.validateMediaUri'] = {
    for (final (name, candidate, protocol, room) in [
      ('recorded', url, 'flv', '3197156'),
      ('another room', url, 'flv', '3197157'),
      ('as hls', url, 'hls', '3197156'),
      ('http', url.replaceFirst('https://', 'http://'), 'flv', '3197156'),
      ('other host', url.replaceFirst('tx105.liveplay.live.kugou.com', 'tx105.live.kugou.com'), 'flv', '3197156'),
      ('port', url.replaceFirst('.com/', '.com:8443/'), 'flv', '3197156'),
      ('no txSecret', url.replaceFirst(RegExp(r'txSecret=[^&]+'), 'txSecret='), 'flv', '3197156'),
      ('short txTime', url.replaceFirst('txTime=6ABA00B5', 'txTime=6AB'), 'flv', '3197156'),
      ('fragment', '$url#x', 'flv', '3197156'),
    ])
      name: KugouLiveApi.validateMediaUri(candidate, expectedRoomId: room, protocol: protocol)?.toString(),
  };
  final now = DateTime.utc(2026, 9, 27, 18);
  value['lease'] = {
    for (final candidate in [
      url,
      'https://tx2.liveplay.live.kugou.com/live/x.flv?txTime=6ABA00B5',
      'https://tx2.liveplay.live.kugou.com/live/x.flv?txTime=6AB',
      'https://tx2.liveplay.live.kugou.com/live/x.flv?txTime=12345678901234567',
      'https://tx2.liveplay.live.kugou.com/live/x.flv?txTime=6ab70000',
      'https://tx2.liveplay.live.kugou.com/live/x.flv',
      'not a url %',
    ])
      candidate: {
        'invalidAt': KugouLiveApi.mediaInvalidAt(candidate)?.toUtc().toIso8601String(),
        'refreshAt': KugouLiveApi.mediaRefreshAt(candidate, now: now)?.toUtc().toIso8601String(),
      },
  };
  _write(
    'S04-room-live',
    'KugouLiveSite.getRoomDetailForRefresh + getLiveStatus + getRoomDetail + getRoomDetailForRecording + '
        'getPlayQualites + resolvePlayUrlsRaw + getPlayUrlInvalidAt + getPlayUrlRefreshAt + getPlayUrls + '
        'resolvePlayUrlsForRecoveryRaw + searchRoomsCancellable (with S05-stream-live) + KugouLiveLink + '
        'KugouLiveApi.mediaHeaders + validateMediaUri + mediaInvalidAt + mediaRefreshAt',
    value,
  );
}

/// A phone broadcast (list status 6, room `liveType` 2): the refresh depths
/// (room entry would ask a stream answer that was not recorded).
Future<void> _mobile() async {
  _load(['S04-room-mobile']);
  final site = _site();
  final value = await _roomEntries(site, '50595748', streams: false);
  value['searchRooms'] = await _searches(site, ['50595748']);
  _write(
    'S04-room-mobile',
    'KugouLiveSite.getRoomDetailForRefresh + getLiveStatus + searchRoomsCancellable',
    value,
  );
}

Future<void> _offline() async {
  _load(['S04-room-offline']);
  final site = _site();
  final value = await _roomEntries(site, '1014306');
  value['searchRooms'] = await _searches(site, ['1014306', 'https://fanxing.kugou.com/1014306']);
  _write(
    'S04-room-offline',
    'KugouLiveSite.getRoomDetailForRefresh + getLiveStatus + getRoomDetail + getRoomDetailForRecording + '
        'getPlayQualites + resolvePlayUrlsForRecoveryRaw + searchRoomsCancellable',
    value,
  );
}

/// Room 999 does not exist: `kugouId` 0 and no name.
Future<void> _notFound() async {
  _load(['S04-room-notfound']);
  final site = _site();
  final value = await _roomEntries(site, '999', streams: false);
  value['getRoomDetail'] = await _outcome(
    () => site.getRoomDetail(roomId: '999', platform: 'kugoulive'),
    _roomProjection,
  );
  value['searchRooms'] = await _searches(site, ['999', 'https://fanxing.kugou.com/999']);
  _write(
    'S04-room-notfound',
    'KugouLiveSite.getRoomDetailForRefresh + getLiveStatus + getRoomDetail + searchRoomsCancellable',
    value,
  );
}

/// The stream answers alone: 3.x's `parseMediaJson`.
Future<void> _streams() async {
  final live = jsonDecode(_body('S05-stream-live'));
  _write('S05-stream-live', 'KugouLiveApi.parseMediaJson', {
    'parseMediaJson(3197156)': _sync(
      () => KugouLiveApi.parseMediaJson(live, expectedRoomId: '3197156'),
      _variants,
    ),
    'parseMediaJson(3197157)': _sync(
      () => KugouLiveApi.parseMediaJson(live, expectedRoomId: '3197157'),
      _variants,
    ),
  });
  final offline = jsonDecode(_body('S05-stream-offline'));
  _write('S05-stream-offline', 'KugouLiveApi.parseMediaJson', {
    'parseMediaJson(1014306)': _sync(
      () => KugouLiveApi.parseMediaJson(offline, expectedRoomId: '1014306'),
      _variants,
    ),
  });
}

/// The keyword search (98 streamers, paged locally by 3.x) and its limits.
Future<void> _search() async {
  _load(['S06-search']);
  final site = _site();
  Future<Object?> search(int page, int pageSize) => _outcome(
    () => site.searchRoomsCancellable('唱歌', page: page, pageSize: pageSize, cancel: CancelToken()),
    _rooms,
  );
  final value = <String, Object?>{
    'searchRooms(1, 30)': await search(1, 30),
    'searchRooms(2, 30)': await search(2, 30),
    'searchRooms(4, 30)': await search(4, 30),
    'searchRooms(5, 30)': await search(5, 30),
    'searchRooms(1, 100)': await search(1, 100),
    'searchRooms(1, 101)': await search(1, 101),
    'searchRooms(0, 30)': await search(0, 30),
    'searchRooms(1, 0)': await search(1, 0),
    'searchRooms(blank)': await _outcome(() => site.searchRooms('  '), _rooms),
    'searchRooms(101 characters)': await _outcome(() => site.searchRooms('歌' * 101), _rooms),
    'parseSearchJsonp(other callback)': _sync(
      () => KugouLiveApi.parseSearchJsonp(_body('S06-search'), callback: 'other'),
      (rooms) => rooms.length,
    ),
    'parseSearchJsonp(no callback check)': _sync(
      () => KugouLiveApi.parseSearchJsonp(_body('S06-search')),
      (rooms) => rooms.length,
    ),
  };
  _write('S06-search', 'KugouLiveSite.searchRoomsCancellable + KugouLiveApi.parseSearchJsonp', value);
}

Future<void> _searchEmpty() async {
  _load(['S06-search-empty']);
  final site = _site();
  _write('S06-search-empty', 'KugouLiveSite.searchRoomsCancellable', {
    'searchRooms(qzxqzxpurelivezz)': await _outcome(
      () => site.searchRoomsCancellable('qzxqzxpurelivezz', page: 1, pageSize: 30, cancel: CancelToken()),
      _rooms,
    ),
  });
}

// 3.x's i18n (assets/translations/zh.json) ------------------------------------

const Map<String, String> _zh = {
  'site_kugoulive': '酷狗直播',
  'kugoulive_directory_scope':
      '官网推荐与分类目录采用原生分页；原生搜索同时返回开播和未开播主播，精确房间号及 fanxing.kugou.com 官方链接可直接解析房间状态。',
  'kugoulive_chat_notice':
      '酷狗远端聊天尚待接入；viewerNum/getViewerNum 按当前观看人数展示，hot 按平台热度展示，fansCount 单独作为粉丝数。',
  'kugoulive_restricted_notice': '该酷狗直播受访问范围限制，界面保持未知状态，不将其显示成未开播。',
  'kugoulive_quality_rate': '{protocol} 码率档 {rate}',
};

/// EasyLocalization's `tr` with named arguments.
String i18n(String key, {Map<String, String>? args}) {
  var text = _zh[key] ?? (throw StateError('No zh.json text for $key'));
  for (final entry in (args ?? const <String, String>{}).entries) {
    text = text.replaceAll('{${entry.key}}', entry.value);
  }
  return text;
}

// Dio's CancelToken (the members 3.x used) and 3.x's request scope -----------

class CancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancel => _cancelled.future;

  void cancel([Object? reason]) {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// 3.x's core/common/request_scope.dart, unchanged.
Future<T> withRequestCancellation<T>(CancelToken? caller, Future<T> Function(CancelToken transport) consume) async {
  final transport = CancelToken();
  if (caller?.isCancelled == true) transport.cancel();
  final forwarding = caller?.whenCancel.asStream().listen((_) {
    if (!transport.isCancelled) transport.cancel();
  });
  try {
    return await consume(transport);
  } finally {
    await forwarding?.cancel();
    if (!transport.isCancelled) transport.cancel();
    await transport.whenCancel;
  }
}

// 3.x models (the parts the Kugou Live adapter uses) --------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

/// 3.x's core/common/http_header_policy.dart `normalize` (the parts used).
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
  LiveDirectoryPage({required Iterable<LiveRoom> rooms, required this.page, required this.hasMore, this.nextCursor})
    : rooms = List.unmodifiable(rooms);
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

// 3.x's kugou_live_link.dart (unchanged) --------------------------------------

abstract final class KugouLiveLink {
  static final RegExp _roomId = RegExp(r'^[1-9]\d{2,10}$');
  static const Set<String> _hosts = {'fanxing.kugou.com', 'mfanxing.kugou.com'};

  static String watchUrl(String raw) => 'https://fanxing.kugou.com/${requireRoomId(raw)}';

  static String requireRoomId(String raw) {
    final value = parseRoomId(raw);
    if (value == null) throw const FormatException('Invalid Kugou Live room identity');
    return value;
  }

  static String? parseRoomId(String raw) {
    final value = raw.trim();
    if (_roomId.hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        !_hosts.contains(uri.host.toLowerCase()) ||
        (uri.hasPort && uri.port != 80 && uri.port != 443) ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList(growable: false);
    if (segments.length == 1 && _roomId.hasMatch(segments.single)) return segments.single;
    final queryId = uri.queryParameters['roomId']?.trim();
    return segments.isEmpty && queryId != null && _roomId.hasMatch(queryId) ? queryId : null;
  }
}

// 3.x's kugou_live_api.dart (imports, `_defaultRequest` and `_readBody` left
// out; the transport must be injected) ---------------------------------------

enum KugouLiveFailure {
  transport,
  access,
  missing,
  rateLimited,
  service,
  schema,
  identity,
  cancelled,
  mediaUnavailable,
}

final class KugouLiveException implements Exception {
  const KugouLiveException(this.kind);

  final KugouLiveFailure kind;

  @override
  String toString() => 'Kugou Live ${kind.name}';
}

enum KugouLiveState { live, offline, restricted, unknown }

final class KugouLiveCategory {
  const KugouLiveCategory({required this.id, required this.name});

  final String id;
  final String name;
}

final class KugouLiveVariant {
  KugouLiveVariant({
    required this.id,
    required this.protocol,
    required this.rate,
    required this.codec,
    required this.layout,
    required Iterable<Uri> urls,
  }) : urls = List.unmodifiable(urls);

  final String id;
  final String protocol;
  final int rate;
  final int codec;
  final int layout;
  final List<Uri> urls;
}

final class KugouLiveRoom {
  KugouLiveRoom({
    required this.roomId,
    required this.userId,
    required this.kugouId,
    required this.nick,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.currentViewers,
    required this.followers,
    required this.popularity,
    required this.state,
    required Iterable<KugouLiveVariant> variants,
  }) : variants = List.unmodifiable(variants);

  final String roomId;
  final String userId;
  final String kugouId;
  final String nick;
  final String title;
  final String avatar;
  final String cover;
  final int? currentViewers;
  final int? followers;
  final int? popularity;
  final KugouLiveState state;
  final List<KugouLiveVariant> variants;

  KugouLiveRoom enrich(KugouLiveRoom known) => KugouLiveRoom(
    roomId: roomId,
    userId: userId.isEmpty ? known.userId : userId,
    kugouId: kugouId.isEmpty ? known.kugouId : kugouId,
    nick: nick == 'Kugou Live' ? known.nick : nick,
    title: title == 'Kugou Live' ? known.title : title,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    cover: cover.isEmpty ? known.cover : cover,
    currentViewers: currentViewers ?? known.currentViewers,
    followers: followers ?? known.followers,
    popularity: popularity ?? known.popularity,
    state: state,
    variants: variants,
  );
}

final class KugouLivePage {
  KugouLivePage({required Iterable<KugouLiveRoom> rooms, required this.hasMore}) : rooms = List.unmodifiable(rooms);

  final List<KugouLiveRoom> rooms;
  final bool hasMore;
}

typedef KugouLiveRequest = Future<({int status, String body})> Function(
  Uri uri,
  Map<String, String> headers,
  CancelToken cancel,
);

class KugouLiveApi {
  KugouLiveApi({required KugouLiveRequest request, this.deadline = const Duration(seconds: 20)}) : _request = request;

  static const String webOrigin = 'https://fanxing.kugou.com';
  static const String apiOrigin = 'https://fx1.service.kugou.com';
  static const int responseLimit = 4 * 1024 * 1024;
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  static const Map<String, String> apiHeaders = {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Origin': webOrigin,
    'Referer': '$webOrigin/',
  };
  static const List<KugouLiveCategory> fallbackCategories = [
    KugouLiveCategory(id: '8000', name: '推荐'),
    KugouLiveCategory(id: '100001', name: '一起玩'),
    KugouLiveCategory(id: '100002', name: '音乐'),
    KugouLiveCategory(id: '31050', name: '高清'),
    KugouLiveCategory(id: '7024', name: '舞蹈'),
    KugouLiveCategory(id: '1009', name: '颜值'),
    KugouLiveCategory(id: '1001', name: '新秀'),
    KugouLiveCategory(id: '3007', name: '酷次元'),
    KugouLiveCategory(id: '7041', name: '搞笑'),
    KugouLiveCategory(id: '31', name: '国风'),
    KugouLiveCategory(id: '6201', name: '游戏女神'),
    KugouLiveCategory(id: '6007', name: '王者荣耀'),
    KugouLiveCategory(id: '6004', name: '和平精英'),
    KugouLiveCategory(id: '6003', name: '网游竞技'),
  ];

  static Map<String, String> mediaHeaders(String roomId) => {
    'User-Agent': userAgent,
    'Origin': webOrigin,
    'Referer': KugouLiveLink.watchUrl(roomId),
  };

  final KugouLiveRequest _request;
  final Duration deadline;

  Future<T> _scope<T>(CancelToken? caller, Future<T> Function(CancelToken) work) =>
      withRequestCancellation(caller, (transport) async {
        if (transport.isCancelled) throw const KugouLiveException(KugouLiveFailure.cancelled);
        try {
          return await Future.any<T>([
            work(transport),
            transport.whenCancel.then<T>((_) => throw const KugouLiveException(KugouLiveFailure.cancelled)),
          ]).timeout(deadline);
        } on TimeoutException {
          throw const KugouLiveException(KugouLiveFailure.transport);
        } catch (error) {
          if (caller?.isCancelled == true || transport.isCancelled) {
            throw const KugouLiveException(KugouLiveFailure.cancelled);
          }
          if (error is KugouLiveException) rethrow;
          throw const KugouLiveException(KugouLiveFailure.transport);
        }
      });

  Future<String> _get(Uri uri, Map<String, String> headers, CancelToken cancel) async {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw const KugouLiveException(KugouLiveFailure.identity);
    }
    final response = await _request(uri, headers, cancel);
    _throwStatus(response.status);
    if (response.body.length > responseLimit) throw const KugouLiveException(KugouLiveFailure.schema);
    return response.body;
  }

  Future<List<KugouLiveCategory>> categories({CancelToken? cancel}) => _scope(cancel, (token) async {
    final body = await _get(Uri.parse('$webOrigin/'), apiHeaders, token);
    return parseCategoriesHtml(body);
  });

  Future<KugouLivePage> directory({required int page, String categoryId = '8000', CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        if (page < 1 || page > 10000 || !RegExp(r'^\d{1,8}$').hasMatch(categoryId)) {
          throw const KugouLiveException(KugouLiveFailure.schema);
        }
        final recommend = categoryId == '8000';
        final query = <String, String>{
          'pid': '0',
          'kugouId': '0',
          'doubleLiveFirst': '1',
          'sysVersion': '0',
          'platform': '7',
          'device': 'PureLive-Web',
          'channel': '0',
          'version': '99999',
          'longitude': '0',
          'latitude': '0',
          'appid': '1010',
          'liveTypeFilter': '0',
          'isNew': '0',
          'entranceType': '0',
          'uiMode': '0',
          'page': '$page',
          if (!recommend) 'cid': categoryId,
        };
        final path = recommend ? '/mfanxing-home/h5/cdn/room/index/list' : '/mfanxing-home/h5/cdn/room/index/list_v4';
        final value = _decode(
          await _get(Uri.parse('$apiOrigin$path').replace(queryParameters: query), apiHeaders, token),
        );
        return parseDirectoryJson(value);
      });

  Future<List<KugouLiveRoom>> search(String keyword, {CancelToken? cancel}) => _scope(cancel, (token) async {
    final query = keyword.trim();
    if (query.isEmpty || query.length > 100) throw const KugouLiveException(KugouLiveFailure.identity);
    final callback = 'pureLive${DateTime.now().microsecondsSinceEpoch}';
    final uri = Uri.parse('$apiOrigin/pt_search/pcsearch/v1/type_all.jsonp')
        .replace(queryParameters: {'keywords': query, 'nums': '200,0,0,0', 'callback': callback});
    final body = await _get(uri, apiHeaders, token);
    return parseSearchJsonp(body, callback: callback);
  });

  Future<KugouLiveRoom> room(String rawRoomId, {bool includeMedia = false, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        final roomId = KugouLiveLink.parseRoomId(rawRoomId);
        if (roomId == null) throw const KugouLiveException(KugouLiveFailure.identity);
        final uri = Uri.parse('https://service2.fanxing.kugou.com/roomcen/room/web/cdn/getEnterRoomInfo')
            .replace(queryParameters: {'roomId': roomId});
        var result = parseRoomJson(_decode(await _get(uri, apiHeaders, token)), expectedRoomId: roomId);
        if (includeMedia && result.state == KugouLiveState.live) {
          final mediaUri = Uri.parse('$apiOrigin/video/pc/live/pull/mutiline/streamaddr').replace(
            queryParameters: {
              'std_rid': roomId,
              'std_plat': '7',
              'std_kid': '0',
              'streamType': '1-2-4-5-8',
              'ua': 'fx-flash',
              'targetLiveTypes': '1-5-6',
              'version': '1000',
              'supportEncryptMode': '1',
              'appid': '1010',
              '_': '${DateTime.now().millisecondsSinceEpoch}',
            },
          );
          final variants = parseMediaJson(_decode(await _get(mediaUri, apiHeaders, token)), expectedRoomId: roomId);
          result = KugouLiveRoom(
            roomId: result.roomId,
            userId: result.userId,
            kugouId: result.kugouId,
            nick: result.nick,
            title: result.title,
            avatar: result.avatar,
            cover: result.cover,
            currentViewers: result.currentViewers,
            followers: result.followers,
            popularity: result.popularity,
            state: result.state,
            variants: variants,
          );
        }
        return result;
      });

  static List<KugouLiveCategory> parseCategoriesHtml(String body) {
    final pattern = RegExp(
      r'''href=["'](?:https://fanxing\.kugou\.com)?/pcindex/category/(\d{1,8})[^"']*["'][^>]*title=["']([^"']+)["']''',
      caseSensitive: false,
    );
    final categories = <KugouLiveCategory>[];
    final seen = <String>{};
    const personalRoutes = {'3001', '3009', '3014', '3015'};
    for (final match in pattern.allMatches(body)) {
      final id = match.group(1)!;
      final name = _htmlText(match.group(2)!);
      if (!personalRoutes.contains(id) && name.isNotEmpty && seen.add(id)) {
        categories.add(KugouLiveCategory(id: id, name: name));
      }
    }
    if (categories.isEmpty) return fallbackCategories;
    return List.unmodifiable(categories);
  }

  static KugouLivePage parseDirectoryJson(Object? value) {
    final data = _responseData(value);
    final rooms = <KugouLiveRoom>[];
    final seen = <String>{};
    for (final entry in _list(data['list'])) {
      final wrapper = _map(entry);
      final raw = wrapper['uiType'] == 'star' ? _map(wrapper['data']) : wrapper;
      final room = _card(raw);
      if (room != null && seen.add(room.roomId)) rooms.add(room);
    }
    return KugouLivePage(rooms: rooms, hasMore: _truthy(data['hasNextPage']));
  }

  static List<KugouLiveRoom> parseSearchJsonp(String body, {String? callback}) {
    final text = body.trim();
    final open = text.indexOf('(');
    final close = text.lastIndexOf(')');
    if (open <= 0 || close <= open || text.substring(close + 1).trim().replaceAll(';', '').isNotEmpty) {
      throw const KugouLiveException(KugouLiveFailure.schema);
    }
    final actual = text.substring(0, open).trim();
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$.]*$').hasMatch(actual) || (callback != null && actual != callback)) {
      throw const KugouLiveException(KugouLiveFailure.schema);
    }
    final root = _map(_decode(text.substring(open + 1, close)));
    final code = _integer(root['status'] ?? root['code']);
    if (code != null && code != 0 && code != 1) {
      throw const KugouLiveException(KugouLiveFailure.service);
    }
    final anchor = _map(_map(root['data'])['anchor']);
    final rooms = <KugouLiveRoom>[];
    final seen = <String>{};
    for (final value in _list(anchor['list'])) {
      final room = _card(_map(value));
      if (room != null && seen.add(room.roomId)) rooms.add(room);
    }
    return List.unmodifiable(rooms);
  }

  static KugouLiveRoom parseRoomJson(Object? value, {required String expectedRoomId}) {
    final roomId = KugouLiveLink.parseRoomId(expectedRoomId);
    if (roomId == null) throw const KugouLiveException(KugouLiveFailure.identity);
    final data = _responseData(value);
    final normal = _map(data['normalRoomInfo']);
    if (normal.isEmpty || (_string(normal['nickName']).isEmpty && _string(normal['kugouId']).isEmpty)) {
      throw const KugouLiveException(KugouLiveFailure.missing);
    }
    final limit = _integer(normal['limitType']) ?? 0;
    final liveType = _integer(data['liveType']);
    final session = _string(data['liveSessionId']);
    final state = limit > 0
        ? KugouLiveState.restricted
        : liveType == -1
        ? KugouLiveState.offline
        : session.isNotEmpty
        ? KugouLiveState.live
        : KugouLiveState.unknown;
    final nick = _string(normal['nickName']);
    return KugouLiveRoom(
      roomId: roomId,
      userId: _string(normal['userId']),
      kugouId: _string(normal['kugouId']),
      nick: nick.isEmpty ? 'Kugou Live' : nick,
      title: _firstText([normal['publicMesg'], normal['privateMesg'], nick], fallback: 'Kugou Live'),
      avatar: _image(_string(normal['userLogo'])),
      cover: _image(_string(normal['imgPath'])),
      currentViewers: null,
      followers: _integer(normal['fansCount']),
      popularity: null,
      state: state,
      variants: const [],
    );
  }

  static List<KugouLiveVariant> parseMediaJson(Object? value, {required String expectedRoomId}) {
    final roomId = KugouLiveLink.parseRoomId(expectedRoomId);
    if (roomId == null) throw const KugouLiveException(KugouLiveFailure.identity);
    final data = _responseData(value);
    if (_string(data['roomId']) != roomId || _integer(data['status']) != 1) {
      throw const KugouLiveException(KugouLiveFailure.mediaUnavailable);
    }
    final grouped = <String, ({String protocol, int rate, int codec, int layout, List<Uri> urls})>{};
    for (final lineValue in _list(data['lines'])) {
      final line = _map(lineValue);
      for (final profileValue in _list(line['streamProfiles'])) {
        final profile = _map(profileValue);
        final rate = _integer(profile['rate']) ?? 0;
        final codec = _integer(profile['codec']) ?? 0;
        final layout = _integer(profile['layout']) ?? 0;
        for (final source in const [('httpsFlv', 'flv'), ('httpsHls', 'hls')]) {
          final protocol = source.$2;
          final id = '$protocol:$rate:$codec:$layout';
          final bucket = grouped.putIfAbsent(
            id,
            () => (protocol: protocol, rate: rate, codec: codec, layout: layout, urls: <Uri>[]),
          );
          for (final raw in _list(profile[source.$1])) {
            final uri = validateMediaUri(_string(raw), expectedRoomId: roomId, protocol: protocol);
            if (uri != null && !bucket.urls.contains(uri)) bucket.urls.add(uri);
          }
        }
      }
    }
    final variants =
        grouped.entries
            .where((entry) => entry.value.urls.isNotEmpty)
            .map(
              (entry) => KugouLiveVariant(
                id: entry.key,
                protocol: entry.value.protocol,
                rate: entry.value.rate,
                codec: entry.value.codec,
                layout: entry.value.layout,
                urls: entry.value.urls,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => right.rate.compareTo(left.rate));
    if (variants.isEmpty) throw const KugouLiveException(KugouLiveFailure.mediaUnavailable);
    return List.unmodifiable(variants);
  }

  static Uri? validateMediaUri(String raw, {required String expectedRoomId, required String protocol}) {
    final uri = Uri.tryParse(raw);
    final expectedExtension = protocol == 'hls' ? '.m3u8' : '.flv';
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443) ||
        !(uri.host == 'liveplay.live.kugou.com' || uri.host.endsWith('.liveplay.live.kugou.com')) ||
        !uri.path.startsWith('/live/') ||
        !uri.path.toLowerCase().endsWith(expectedExtension) ||
        _string(uri.queryParameters['txSecret']).isEmpty ||
        !RegExp(r'^[0-9A-Fa-f]{8,16}$').hasMatch(_string(uri.queryParameters['txTime']))) {
      return null;
    }
    final token = uri.queryParameters['token'] ?? '';
    return token.startsWith('0-$expectedRoomId-') ? uri : null;
  }

  static DateTime? mediaInvalidAt(String raw) {
    final uri = Uri.tryParse(raw);
    final value = uri?.queryParameters['txTime'];
    if (value == null || !RegExp(r'^[0-9A-Fa-f]{8,16}$').hasMatch(value)) return null;
    final seconds = int.tryParse(value, radix: 16);
    return seconds == null ? null : DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  static DateTime? mediaRefreshAt(String raw, {DateTime? now}) {
    final invalid = mediaInvalidAt(raw);
    if (invalid == null) return null;
    final current = now ?? DateTime.now();
    final refresh = invalid.subtract(const Duration(minutes: 5));
    return refresh.isAfter(current) ? refresh : current;
  }

  static KugouLiveRoom? _card(Map<String, Object?> raw) {
    final roomId = KugouLiveLink.parseRoomId(_string(raw['roomId']));
    if (roomId == null) return null;
    final live = _integer(raw['liveStatus'] ?? raw['status'] ?? raw['liveType']);
    final state = live == 1
        ? KugouLiveState.live
        : live == 0 || live == -1
        ? KugouLiveState.offline
        : KugouLiveState.unknown;
    final nick = _string(raw['nickName']);
    return KugouLiveRoom(
      roomId: roomId,
      userId: _string(raw['userId']),
      kugouId: _string(raw['kugouId']),
      nick: nick.isEmpty ? 'Kugou Live' : nick,
      title: _firstText([raw['label'], raw['topicContent'], raw['performContent'], nick], fallback: 'Kugou Live'),
      avatar: _image(_string(raw['userLogo'] ?? raw['logo'])),
      cover: _image(_string(raw['imgPath'] ?? raw['imagePath'])),
      currentViewers: _integer(raw['viewerNum'] ?? raw['getViewerNum']),
      followers: _integer(raw['fansCount']),
      popularity: _integer(raw['hot']),
      state: state,
      variants: const [],
    );
  }

  static Map<String, Object?> _responseData(Object? value) {
    final root = _map(value);
    final code = _integer(root['code']);
    if (code != 0) throw const KugouLiveException(KugouLiveFailure.service);
    final data = _map(root['data']);
    if (data.isEmpty) throw const KugouLiveException(KugouLiveFailure.schema);
    return data;
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const KugouLiveException(KugouLiveFailure.schema);
    }
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) return const {};
    return value.map((key, value) => MapEntry('$key', value));
  }

  static List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

  static String _string(Object? value) => value == null ? '' : '$value'.trim();

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_string(value));
  }

  static bool _truthy(Object? value) => value == true || _integer(value) == 1;

  static String _firstText(List<Object?> values, {required String fallback}) {
    for (final value in values) {
      final text = _string(value);
      if (text.isNotEmpty && text != 'null') return text;
    }
    return fallback;
  }

  static String _image(String raw) {
    var value = raw.trim();
    if (value.isEmpty || value == 'null') return '';
    value = value.replaceFirst('/v2/fxuserlogo//v2/fxuserlogo/', '/v2/fxuserlogo/');
    if (value.startsWith('//')) value = 'https:$value';
    if (value.startsWith('/')) value = 'https://p3.fx.kgimg.com$value';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 80 && uri.port != 443) ||
        !(uri.host == 'kgimg.com' ||
            uri.host.endsWith('.kgimg.com') ||
            uri.host == 'kugou.com' ||
            uri.host.endsWith('.kugou.com'))) {
      return '';
    }
    if (uri.scheme == 'http') value = uri.replace(scheme: 'https').toString();
    return Uri.tryParse(value)?.scheme == 'https' ? value : '';
  }

  static String _htmlText(String raw) => raw
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();

  static void _throwStatus(int status) {
    if (status >= 200 && status < 300) return;
    final failure = switch (status) {
      400 || 422 => KugouLiveFailure.schema,
      401 || 403 || 451 => KugouLiveFailure.access,
      404 || 410 => KugouLiveFailure.missing,
      429 => KugouLiveFailure.rateLimited,
      >= 500 => KugouLiveFailure.service,
      _ => KugouLiveFailure.transport,
    };
    throw KugouLiveException(failure);
  }
}

// 3.x's kugou_live_site.dart (without `extends`/`implements`, `@override`
// and `getDanmaku`; the API must be injected) --------------------------------

final class KugouLiveSite {
  KugouLiveSite({required KugouLiveApi api}) : _api = api;

  final KugouLiveApi _api;
  final Map<String, KugouLiveRoom> _known = {};
  List<KugouLiveCategory>? _categories;

  String get id => 'kugoulive';

  String get name => i18n('site_kugoulive');

  String get directoryNoticeKey => 'kugoulive_directory_scope';

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    if (page != 1 || pageSize < 1) return const [];
    _categories ??= await _api.categories();
    return [
      LiveCategory(
        id: id,
        name: name,
        children: _categories!
            .take(pageSize)
            .map(
              (category) => LiveArea(
                platform: id,
                areaType: 'official',
                areaId: category.id,
                areaName: category.name,
                typeName: name,
              ),
            )
            .toList(growable: false),
      ),
    ];
  }

  String _categoryId(LiveArea? category) {
    if (category == null) return '8000';
    if (category.platform != id || category.areaType != 'official') {
      throw const KugouLiveException(KugouLiveFailure.identity);
    }
    final categoryId = category.areaId?.trim() ?? '';
    final known = _categories ?? KugouLiveApi.fallbackCategories;
    if (!known.any((item) => item.id == categoryId)) {
      throw const KugouLiveException(KugouLiveFailure.identity);
    }
    return categoryId;
  }

  void _remember(Iterable<KugouLiveRoom> rooms) {
    for (final room in rooms) {
      _known[room.roomId] = room;
    }
  }

  static LiveRoom _room(KugouLiveRoom room, {required bool includeMedia}) {
    final online = room.currentViewers?.toString();
    final popularity = room.popularity?.toString();
    final primary = online ?? popularity;
    final notice = <String>[
      if (room.state == KugouLiveState.restricted) i18n('kugoulive_restricted_notice'),
      i18n('kugoulive_chat_notice'),
    ];
    return LiveRoom(
      platform: 'kugoulive',
      roomId: room.roomId,
      userId: room.userId.isEmpty ? room.kugouId : room.userId,
      title: room.title,
      nick: room.nick,
      avatar: room.avatar.isEmpty ? room.cover : room.avatar,
      cover: room.cover,
      area: i18n('site_kugoulive'),
      link: KugouLiveLink.watchUrl(room.roomId),
      liveStatus: switch (room.state) {
        KugouLiveState.live => LiveStatus.live,
        KugouLiveState.offline => LiveStatus.offline,
        KugouLiveState.restricted || KugouLiveState.unknown => LiveStatus.unknown,
      },
      watching: primary ?? '',
      onlineViewers: online,
      popularity: popularity,
      followers: room.followers?.toString(),
      audienceMetricType: online != null
          ? AudienceMetricType.onlineViewers
          : popularity != null
          ? AudienceMetricType.popularity
          : AudienceMetricType.unknown,
      notice: notice.join('\n'),
      httpHeaders: KugouLiveApi.mediaHeaders(room.roomId),
      data: includeMedia ? room : null,
    );
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final result = await _api.directory(page: page, categoryId: _categoryId(category), cancel: cancel);
    _remember(result.rooms);
    return LiveDirectoryPage(
      rooms: result.rooms.map((room) => _room(room, includeMedia: false)),
      page: page,
      hasMore: result.hasMore,
    );
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    final result = await getDirectoryPage(page: page);
    return result.rooms.take(pageSize).toList(growable: false);
  }

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return const [];
    final result = await getDirectoryPage(page: page, category: category);
    return result.rooms.take(pageSize).toList(growable: false);
  }

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final raw = keyword.trim();
    if (raw.isEmpty || page < 1 || pageSize < 1 || pageSize > 100) return const [];
    final roomId = KugouLiveLink.parseRoomId(raw);
    if (roomId != null) {
      if (page != 1) return const [];
      try {
        return [await _detail(roomId, id, includeMedia: false, cancel: cancel)];
      } on KugouLiveException catch (error) {
        if (error.kind == KugouLiveFailure.missing) return const [];
        rethrow;
      }
    }
    final rooms = await _api.search(raw, cancel: cancel);
    _remember(rooms);
    final start = (page - 1) * pageSize;
    if (start >= rooms.length) return const [];
    return rooms.skip(start).take(pageSize).map((room) => _room(room, includeMedia: false)).toList(growable: false);
  }

  String _roomId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) {
      throw const KugouLiveException(KugouLiveFailure.identity);
    }
    final value = KugouLiveLink.parseRoomId(roomId);
    if (value == null) throw const KugouLiveException(KugouLiveFailure.identity);
    return value;
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia, CancelToken? cancel}) async {
    final normalized = _roomId(roomId, platform);
    var room = await _api.room(normalized, includeMedia: includeMedia, cancel: cancel);
    final known = _known[normalized];
    if (known != null) room = room.enrich(known);
    _known[normalized] = room;
    return _room(room, includeMedia: includeMedia);
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
      throw const KugouLiveException(KugouLiveFailure.access);
    }
    return room.isLiveNow;
  }

  KugouLiveRoom _snapshot(LiveRoom detail) {
    final roomId = _roomId(detail.roomId ?? '', detail.platform ?? '');
    final room = detail.data;
    if (room is! KugouLiveRoom || room.roomId != roomId) {
      throw const KugouLiveException(KugouLiveFailure.identity);
    }
    if (room.state != KugouLiveState.live || room.variants.isEmpty) {
      throw const KugouLiveException(KugouLiveFailure.mediaUnavailable);
    }
    return room;
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    _roomId(detail.roomId ?? '', detail.platform ?? '');
    if (detail.isExplicitlyOfflineNow) return const [];
    final room = _snapshot(detail);
    return List.unmodifiable(
      room.variants.map(
        (variant) => LivePlayQuality(
          id: variant.id,
          quality: i18n(
            'kugoulive_quality_rate',
            args: {'protocol': variant.protocol.toUpperCase(), 'rate': '${variant.rate}'},
          ),
          sort: variant.rate * 10 + (variant.protocol == 'hls' ? 1 : 2),
        ),
      ),
    );
  }

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality, {required bool refresh}) async {
    var room = _snapshot(detail);
    if (refresh) room = _snapshot(await _detail(room.roomId, id, includeMedia: true));
    final selectionId = quality.selectionId.toString();
    for (final variant in room.variants) {
      if (variant.id != selectionId) continue;
      return LivePlayUrlResolution(
        urls: variant.urls.map((uri) => uri.toString()).toList(growable: false),
        appliedQualityData: variant.id,
      );
    }
    throw const KugouLiveException(KugouLiveFailure.mediaUnavailable);
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) =>
      _resolve(detail, quality, refresh: false);

  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality, refresh: true);

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await _resolve(detail, quality, refresh: false)).urls;

  DateTime? getPlayUrlRefreshAt(String url, {DateTime? now}) => KugouLiveApi.mediaRefreshAt(url, now: now);

  DateTime? getPlayUrlInvalidAt(String url, {DateTime? now}) => KugouLiveApi.mediaInvalidAt(url);
}
