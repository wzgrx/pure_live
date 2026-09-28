// Writes expected.json for the Baidu Live samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.30-baidulive.md, "v3 的冻结输出").
//
// The archive has no Baidu Live expected.json (its legacy harness only
// covered five platforms, and 3.x no longer builds). The code below the
// models is 3.x's BaiduLiveApi, BaiduLiveLink and BaiduLiveSite, copied from
// legacy/lib/core/site/baidulive/ (archive/v4). 3.x already injected its
// transport (`BaiduLiveRequest`), so only that function is replaced: it
// answers from the samples by method, host and path, a feed POST by its form
// fields other than the device id, clock and signature (`uid`, `timestamp`,
// `sign`), a room GET by its query other than the device id and clock (`uid`,
// `_`) and by the room id inside `data` (whose `device_id` changes every
// run), with the recorded status (all samples are 200; 3.x's `_throwStatus`
// fails any status outside 2xx before reading the body). A request
// without a sample is a StateError; 3.x's `_scope` would turn it into
// `transport`, so it is also kept aside and rethrown after the call: a
// missing sample fails the run. The recorded requests write `<device>`,
// `<time>` and `<sign>` for those values, and hold the parsed query and form:
// 3.x's Dart `Uri` encoding wrote empty fields bare (`sid&`, `bd_vid&`)
// where the recorder wrote `sid=&`, which the platform reads alike.
//
// `_defaultRequest` and `_readBody` (the network path) are left out and the
// API's constructor needs the transport; Dio's CancelToken is reduced to the
// members 3.x used and 3.x's `withRequestCancellation`
// (core/common/request_scope.dart) is copied unchanged. `BaiduLiveSite` keeps
// its method bodies without `extends`, `implements`, `@override` and
// `getDanmaku` (`EmptyDanmaku`); its constructor needs the API injected.
// `i18n` returns 3.x's zh.json text with easy_localization's `{name}`
// arguments. 3.x's LiveRoom, LiveArea, LiveCategory, LivePlayQuality,
// LivePlayUrlResolution and LiveDirectoryPage are reduced to the parts these
// classes use. The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`); every entry also records the
// requests it made.
//
// Run from the repository root: dart run fixtures/baidulive/legacy_expected.dart
// (package:crypto, 3.x's md5 dependency, is in the workspace). Review the
// diff of every expected.json before committing it.
// ignore_for_file: type=lint, unused_field, unused_element
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _root = 'fixtures/baidulive';
const _platform = 'baidulive';
const _liveRoom = '11560887291';
const _endedRoom = '11583715413';
const _missingRoom = '99999999999';

void main() async {
  await _feedRecommend();
  await _feedSecondPage();
  await _feedShopping();
  await _roomLive();
  await _roomEnded();
  await _roomNotFound();
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final List<Map<String, Object?>> _requests = [];
String? _missingSample;

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync())
        as Map<String, dynamic>;

void _load(List<String> samples) {
  _samples = [for (final sample in samples) _meta(sample)];
  _requests.clear();
  _missingSample = null;
}

const _volatileForm = {'uid', 'timestamp', 'sign'};
const _volatileQuery = {'uid', '_', 'data'};

Map<String, String> _without(Map<String, String> fields, Set<String> left) => {
  for (final entry in fields.entries)
    if (!left.contains(entry.key)) entry.key: entry.value,
};

bool _same(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

/// The room id inside a room request's `data` JSON, or null.
String? _dataRoomId(Map<String, String> query) {
  final raw = query['data'];
  if (raw == null) return null;
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return (decoded['data'] as Map<String, dynamic>)['room_id'] as String?;
}

/// A request as recorded in expected.json: the device id, clocks and
/// signature written as placeholders.
Map<String, Object?> _describe(
  Uri uri,
  Map<String, String> headers,
  Map<String, String>? form,
) {
  String data(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    (decoded['data'] as Map<String, dynamic>)['device_id'] = '<device>';
    return jsonEncode(decoded);
  }

  return {
    'method': form == null ? 'GET' : 'POST',
    'url': '${uri.scheme}://${uri.host}${uri.path}',
    if (uri.queryParameters.isNotEmpty)
      'query': {
        for (final entry in uri.queryParameters.entries)
          entry.key: switch (entry.key) {
            'uid' => '<device>',
            '_' => '<time>',
            'data' => data(entry.value),
            _ => entry.value,
          },
      },
    if (form != null)
      'form': {
        for (final entry in form.entries)
          entry.key: switch (entry.key) {
            'uid' => '<device>',
            'timestamp' => '<time>',
            'sign' => '<sign>',
            _ => entry.value,
          },
      },
    'headers': headers,
  };
}

/// 3.x's transport over the samples: no redirect following, and the body is
/// read only for a 200.
Future<({int status, String body})> _replay(
  Uri uri,
  Map<String, String> headers,
  Map<String, String>? form,
  CancelToken cancel,
) async {
  _requests.add(_describe(uri, headers, form));
  final method = form == null ? 'GET' : 'POST';
  final meta = _samples.where((meta) {
    final request = meta['request'] as Map<String, dynamic>;
    if (request['method'] != method) return false;
    final recorded = Uri.parse(request['url'] as String);
    if (recorded.host != uri.host || recorded.path != uri.path) return false;
    if (!_same(
      _without(recorded.queryParameters, _volatileQuery),
      _without(uri.queryParameters, _volatileQuery),
    )) {
      return false;
    }
    if (_dataRoomId(recorded.queryParameters) !=
        _dataRoomId(uri.queryParameters)) {
      return false;
    }
    final body = request['body'];
    final recordedForm = body is String && body.isNotEmpty
        ? Uri.splitQueryString(body)
        : const <String, String>{};
    return _same(
      _without(recordedForm, _volatileForm),
      _without(form ?? const {}, _volatileForm),
    );
  }).firstOrNull;
  if (meta == null) {
    _missingSample = 'No recorded sample for $method $uri $form';
    throw StateError(_missingSample!);
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

/// [body]'s projection with the requests it made.
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
  final missing = _missingSample;
  if (missing != null) throw StateError(missing);
  return {
    'requests': [for (final request in _requests.skip(before)) request],
    'value': value,
  };
}

Object? _sync(Object? Function() body) {
  try {
    return body();
  } on Object catch (error) {
    return _errorProjection(error);
  }
}

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere(
    (key, value) =>
        value == null ||
        (value is Map && value.isEmpty) ||
        (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(Iterable<LiveRoom> rooms) => [
  for (final room in rooms) _roomProjection(room),
];

Map<String, dynamic> _pageProjection(LiveDirectoryPage page) => {
  'page': page.page,
  'hasMore': page.hasMore,
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

List<Map<String, dynamic>> _categoriesProjection(
  List<LiveCategory> categories,
) => [
  for (final category in categories)
    {
      'id': category.id,
      'name': category.name,
      'children': [for (final area in category.children) area.toJson()],
    },
];

Map<String, dynamic> _parsedRoom(BaiduLiveRoom room) => {
  'roomId': room.roomId,
  'userId': room.userId,
  'nick': room.nick,
  'title': room.title,
  'avatar': room.avatar,
  'cover': room.cover,
  'category': room.category,
  'currentViewers': room.currentViewers,
  'followers': room.followers,
  'state': room.state.name,
  'variants': [
    for (final variant in room.variants)
      {
        'id': variant.id,
        'protocol': variant.protocol,
        'resolution': variant.resolution,
        'codec': variant.codec,
        'urls': [for (final url in variant.urls) '$url'],
      },
  ],
};

Map<String, dynamic> _parsedPage(BaiduLivePage page) => {
  'sessionId': page.sessionId,
  'refreshIndex': page.refreshIndex,
  'hasMore': page.hasMore,
  'categories': [
    for (final category in page.categories)
      {
        'id': category.id,
        'name': category.name,
        'channelId': category.channelId,
      },
  ],
  'rooms': [for (final room in page.rooms) _parsedRoom(room)],
};

String _body(String sample) {
  final meta = _meta(sample);
  return File('$_root/$sample/${meta['body']}').readAsStringSync();
}

/// The recorded feed form and 3.x's signature of it (without `sign`).
Map<String, Object?> _signature(String sample) {
  final request = _meta(sample)['request'] as Map<String, dynamic>;
  final form = Uri.splitQueryString(request['body'] as String);
  return {
    'recorded': form['sign'],
    'signFeedParameters': BaiduLiveApi.signFeedParameters(form),
  };
}

// Samples ---------------------------------------------------------------------

/// The catalog before and after the first feed page, the first page by every
/// entry 3.x had, and the calls 3.x answered without a request.
Future<void> _feedRecommend() async {
  _load(['S01-feed-rec-p1']);
  final site = BaiduLiveSite(api: BaiduLiveApi(request: _replay));
  final value = <String, Object?>{
    'name': site.name,
    'directoryNoticeKey': site.directoryNoticeKey,
    'getCategores(1) before the feed': await _outcome(
      () => site.getCategores(1, 30),
      _categoriesProjection,
    ),
    'getCategores(2)': await _outcome(
      () => site.getCategores(2, 30),
      (categories) => categories.length,
    ),
    'getCategores(1, pageSize 0)': await _outcome(
      () => site.getCategores(1, 0),
      (categories) => categories.length,
    ),
    'getDirectoryPage(1)': await _outcome(
      () => site.getDirectoryPage(page: 1),
      _pageProjection,
    ),
    'getCategores(1) after the feed': await _outcome(
      () => site.getCategores(1, 30),
      _categoriesProjection,
    ),
    'getDirectoryPage(0)': await _outcome(
      () => site.getDirectoryPage(page: 0),
      _pageProjection,
    ),
    'getDirectoryPage(3) after page 1': await _outcome(
      () => site.getDirectoryPage(page: 3),
      _pageProjection,
    ),
    'getDirectoryPage(1, another platform)': await _outcome(
      () => site.getDirectoryPage(
        page: 1,
        category: LiveArea(
          platform: 'douyu',
          areaType: 'official',
          areaId: 'rec',
        ),
      ),
      _pageProjection,
    ),
    'getDirectoryPage(1, unknown area)': await _outcome(
      () => site.getDirectoryPage(
        page: 1,
        category: LiveArea(
          platform: _platform,
          areaType: 'official',
          areaId: 'auto',
        ),
      ),
      _pageProjection,
    ),
  };
  final categories = await site.getCategores(1, 30);
  final rec = categories.single.children.first;
  value['getRecommendRooms(1)'] = await _outcome(
    () => site.getRecommendRooms(page: 1),
    _rooms,
  );
  value['getRecommendRooms(1, pageSize 4)'] = await _outcome(
    () => site.getRecommendRooms(page: 1, pageSize: 4),
    _rooms,
  );
  value['getCategoryRooms(rec, 1)'] = await _outcome(
    () => site.getCategoryRooms(rec, page: 1),
    _rooms,
  );
  final first = await site.getDirectoryPage(page: 1);
  value['getPlayQualites(card)'] = await _outcome(
    () => site.getPlayQualites(detail: first.rooms.first),
    (qualities) => [
      for (final quality in qualities) _qualityProjection(quality),
    ],
  );
  value['searchRooms(nickname)'] = await _outcome(
    () => site.searchRooms('锦尚书画'),
    _rooms,
  );
  value['parseDirectoryJson'] = _sync(
    () => _parsedPage(
      BaiduLiveApi.parseDirectoryJson(jsonDecode(_body('S01-feed-rec-p1'))),
    ),
  );
  value['signature'] = _signature('S01-feed-rec-p1');
  value['signFeedParameters(b=2, a=1)'] = BaiduLiveApi.signFeedParameters({
    'b': '2',
    'a': '1',
  });
  _write(
    'S01-feed-rec-p1',
    'BaiduLiveSite.getCategores + getDirectoryPage + getRecommendRooms + getCategoryRooms + getPlayQualites(card) + '
        'searchRooms + BaiduLiveApi.parseDirectoryJson + signFeedParameters',
    value,
  );
}

/// The second page of the same feed session, and the page asked again.
Future<void> _feedSecondPage() async {
  _load(['S01-feed-rec-p1', 'S01-feed-rec-p2']);
  final site = BaiduLiveSite(api: BaiduLiveApi(request: _replay));
  await site.getDirectoryPage(page: 1);
  final value = <String, Object?>{
    'getDirectoryPage(2)': await _outcome(
      () => site.getDirectoryPage(page: 2),
      _pageProjection,
    ),
    'getDirectoryPage(2) again': await _outcome(
      () => site.getDirectoryPage(page: 2),
      _pageProjection,
    ),
  };
  final other = BaiduLiveSite(api: BaiduLiveApi(request: _replay));
  await other.getRecommendRooms(page: 1);
  value['getRecommendRooms(2, pageSize 5)'] = await _outcome(
    () => other.getRecommendRooms(page: 2, pageSize: 5),
    _rooms,
  );
  value['parseDirectoryJson'] = _sync(
    () => _parsedPage(
      BaiduLiveApi.parseDirectoryJson(jsonDecode(_body('S01-feed-rec-p2'))),
    ),
  );
  value['signature'] = _signature('S01-feed-rec-p2');
  _write(
    'S01-feed-rec-p2',
    'BaiduLiveSite.getDirectoryPage(2) after page 1 (with S01-feed-rec-p1) + getRecommendRooms(2) + '
        'BaiduLiveApi.parseDirectoryJson + signFeedParameters',
    value,
  );
}

/// The shopping channel from the fixed catalog.
Future<void> _feedShopping() async {
  _load(['S01-feed-shopping-p1']);
  final site = BaiduLiveSite(api: BaiduLiveApi(request: _replay));
  final shopping = (await site.getCategores(
    1,
    30,
  )).single.children.firstWhere((area) => area.areaId == 'shopping');
  final value = <String, Object?>{
    'getDirectoryPage(1, shopping)': await _outcome(
      () => site.getDirectoryPage(page: 1, category: shopping),
      _pageProjection,
    ),
    'getCategoryRooms(shopping, 1)': await _outcome(
      () => site.getCategoryRooms(shopping, page: 1),
      _rooms,
    ),
    'signature': _signature('S01-feed-shopping-p1'),
  };
  _write(
    'S01-feed-shopping-p1',
    'BaiduLiveSite.getDirectoryPage(1, shopping) + getCategoryRooms(shopping) + signFeedParameters',
    value,
  );
}

/// Every entry 3.x had for one room: room entry, follow refresh, recording
/// detail, state, qualities with their URLs, resolution and recovery.
Future<Map<String, Object?>> _roomEntries(
  BaiduLiveSite site,
  String id, {
  bool streams = true,
}) async {
  final value = <String, Object?>{
    'getRoomDetail': await _outcome(
      () => site.getRoomDetail(roomId: id, platform: _platform),
      _roomProjection,
    ),
    'getRoomDetailForRefresh': await _outcome(
      () => site.getRoomDetailForRefresh(roomId: id, platform: _platform),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _outcome(
      () => site.getRoomDetailForRecording(roomId: id, platform: _platform),
      _roomProjection,
    ),
    'getLiveStatus': await _outcome(
      () => site.getLiveStatus(roomId: id, platform: _platform),
      (live) => live,
    ),
  };
  if (!streams) return value;
  final detail = await site.getRoomDetail(roomId: id, platform: _platform);
  value['getPlayQualites'] = await _outcome(
    () => site.getPlayQualites(detail: detail),
    (qualities) => [
      for (final quality in qualities) _qualityProjection(quality),
    ],
  );
  final qualities = await site.getPlayQualites(detail: detail);
  value['getPlayUrls'] = {
    for (final quality in qualities)
      '${quality.id}': await _outcome(
        () => site.getPlayUrls(detail: detail, quality: quality),
        (urls) => urls,
      ),
  };
  value['resolvePlayUrlsRaw'] = {
    for (final quality in qualities)
      '${quality.id}': await _outcome(
        () => site.resolvePlayUrlsRaw(detail: detail, quality: quality),
        _resolutionProjection,
      ),
  };
  value['resolvePlayUrlsForRecoveryRaw'] = {
    for (final quality in qualities)
      '${quality.id}': await _outcome(
        () =>
            site.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: quality),
        _resolutionProjection,
      ),
  };
  final refreshed = await site.getRoomDetailForRefresh(
    roomId: id,
    platform: _platform,
  );
  value['getPlayQualites(refreshed)'] = await _outcome(
    () => site.getPlayQualites(detail: refreshed),
    (qualities) => [
      for (final quality in qualities) _qualityProjection(quality),
    ],
  );
  return value;
}

Future<Object?> _searches(BaiduLiveSite site, List<String> keywords) async => {
  for (final keyword in keywords)
    keyword: await _outcome(() => site.searchRooms(keyword), _rooms),
};

/// 3.x's link rule over the forms a user may paste.
const _linkVectors = [
  '11560887291',
  ' 11560887291 ',
  '123456',
  '12345',
  '012345678',
  '123456789012345678901',
  'https://live.baidu.com/m/room/11560887291',
  'https://live.baidu.com/m/room/11560887291?source=anchorrooms',
  'https://live.baidu.com/m/room/11560887291/',
  'https://live.baidu.com//m//room//11560887291',
  'https://LIVE.BAIDU.COM/m/room/11560887291',
  'https://live.baidu.com:443/m/room/11560887291',
  'https://live.baidu.com/m/media/pclive/pchome/live.html?room_id=11560887291&source=h5pre',
  'https://live.baidu.com/m/media/multipage/liveshow/index/cdxqdh?room_id=11560887291',
  'https://live.baidu.com/m/media/multipage/liveshow/index/cdx.qdh?room_id=11560887291',
  'https://live.baidu.com/m/media/multipage/liveshow/index?room_id=11560887291',
  'https://live.baidu.com/search?room_id=11560887291',
  'https://live.baidu.com/m/room/11560887291#chat',
  'https://live.baidu.com:8443/m/room/11560887291',
  'https://user@live.baidu.com/m/room/11560887291',
  'https://live.baidu.com.evil.test/m/room/11560887291',
  'http://live.baidu.com/m/room/11560887291',
  'https://live.baidu.com/M/Room/11560887291',
  'https://live.baidu.com/m/room/abc',
  'https://live.baidu.com/m/media/pclive/pchome/live.html?room_id=12',
  'https://live.baidu.com/m/media/pclive/pchome/live.html',
];

/// 3.x's media rule over the hosts, schemes and paths the platform gives.
const _mediaVectors = [
  (
    'http://hls.liveshow.bdstatic.com/live/stream_bduid_6325759471_11560887291-L3.m3u8',
    'hls',
  ),
  (
    'https://hls-live.bdstatic.com/live/stream_bduid_6325759471_11560887291.flv?kabr_spts=-3000',
    'flv',
  ),
  (
    'https://flv-live.bdstatic.com/live/stream_bduid_6325759471_11560887291.flv',
    'flv',
  ),
  (
    'http://flv.liveshow.lss-user.baidubce.com/live/stream_bduid_6325759471_11560887291-L3.flv',
    'flv',
  ),
  (
    'http://hls2.liveshow.lss-user.baidubce.com/live/stream_bduid_6325759471_11560887291-L3/playlist.m3u8',
    'hls',
  ),
  (
    'https://hls-live.bdstatic.com/live/stream_bduid_6325759471_99999999999.flv',
    'flv',
  ),
  (
    'https://hls-live.bdstatic.com/live/stream_bduid_6325759471_11560887291.m3u8',
    'flv',
  ),
  (
    'https://hls-live.bdstatic.com/other/stream_bduid_6325759471_11560887291.flv',
    'flv',
  ),
  (
    'https://hls-live.bdstatic.com:8443/live/stream_bduid_6325759471_11560887291.flv',
    'flv',
  ),
  (
    'https://p2.bdstatic.com/rtmp.liveshow.lss-user.baidubce.com/live/stream_bduid_7108620967_11560887291/merged.m3u8',
    'hls',
  ),
];

Future<void> _roomLive() async {
  _load(['S02-room-live', 'S01-feed-rec-p1']);
  final site = BaiduLiveSite(api: BaiduLiveApi(request: _replay));
  final value = await _roomEntries(site, _liveRoom);
  value['searchRooms'] = await _searches(site, [
    _liveRoom,
    ' $_liveRoom ',
    'https://live.baidu.com/m/room/$_liveRoom',
    'https://live.baidu.com/m/media/pclive/pchome/live.html?room_id=$_liveRoom',
    'https://live.baidu.com/m/media/multipage/liveshow/index/cdxqdh?room_id=$_liveRoom',
  ]);
  value['searchRooms(page 2)'] = await _outcome(
    () => site.searchRooms(_liveRoom, page: 2),
    _rooms,
  );
  value['parseRoomJson'] = _sync(
    () => _parsedRoom(
      BaiduLiveApi.parseRoomJson(
        jsonDecode(_body('S02-room-live')),
        expectedRoomId: _liveRoom,
      ),
    ),
  );
  value['parseRoomJson(another room)'] = _sync(
    () => _parsedRoom(
      BaiduLiveApi.parseRoomJson(
        jsonDecode(_body('S02-room-live')),
        expectedRoomId: _endedRoom,
      ),
    ),
  );
  // A directory card of this room seen before the detail (3.x enriched the
  // detail from it).
  final listed = BaiduLiveSite(api: BaiduLiveApi(request: _replay));
  await listed.getDirectoryPage(page: 1);
  value['getRoomDetail after the directory'] = await _outcome(
    () => listed.getRoomDetail(roomId: _liveRoom, platform: _platform),
    _roomProjection,
  );
  value['BaiduLiveLink.parseRoomId'] = {
    for (final url in _linkVectors) url: _sync(() => BaiduLiveLink.parseRoomId(url)),
  };
  value['BaiduLiveLink.watchUrl'] = BaiduLiveLink.watchUrl(_liveRoom);
  value['BaiduLiveApi.mediaHeaders'] = BaiduLiveApi.mediaHeaders(_liveRoom);
  value['BaiduLiveApi.apiHeaders'] = BaiduLiveApi.apiHeaders;
  value['BaiduLiveApi.validateMediaUri'] = {
    for (final (url, protocol) in _mediaVectors)
      '$protocol $url': _sync(
        () => BaiduLiveApi.validateMediaUri(
          url,
          expectedRoomId: _liveRoom,
          protocol: protocol,
        )?.toString(),
      ),
  };
  _write(
    'S02-room-live',
    'BaiduLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + getPlayUrls + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + searchRooms '
        '(+ S01-feed-rec-p1 for the enriched detail) + BaiduLiveApi.parseRoomJson + validateMediaUri + '
        'BaiduLiveLink',
    value,
  );
}

Future<void> _roomEnded() async {
  _load(['S02-room-ended']);
  final site = BaiduLiveSite(api: BaiduLiveApi(request: _replay));
  final value = await _roomEntries(site, _endedRoom);
  value['searchRooms'] = await _searches(site, [
    _endedRoom,
    'https://live.baidu.com/m/room/$_endedRoom',
  ]);
  value['parseRoomJson'] = _sync(
    () => _parsedRoom(
      BaiduLiveApi.parseRoomJson(
        jsonDecode(_body('S02-room-ended')),
        expectedRoomId: _endedRoom,
      ),
    ),
  );
  _write(
    'S02-room-ended',
    'BaiduLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + searchRooms + BaiduLiveApi.parseRoomJson',
    value,
  );
}

Future<void> _roomNotFound() async {
  _load(['S02-room-notfound']);
  final site = BaiduLiveSite(api: BaiduLiveApi(request: _replay));
  final value = await _roomEntries(site, _missingRoom, streams: false);
  value['searchRooms'] = await _searches(site, [
    _missingRoom,
    'https://live.baidu.com/m/room/$_missingRoom',
  ]);
  value['parseRoomJson'] = _sync(
    () => _parsedRoom(
      BaiduLiveApi.parseRoomJson(
        jsonDecode(_body('S02-room-notfound')),
        expectedRoomId: _missingRoom,
      ),
    ),
  );
  _write(
    'S02-room-notfound',
    'BaiduLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'searchRooms + BaiduLiveApi.parseRoomJson',
    value,
  );
}

// 3.x's i18n (assets/translations/zh.json) ------------------------------------

const Map<String, String> _zh = {
  'site_baidulive': '百度直播',
  'baidulive_directory_scope':
      '官网推荐与七个分类采用原生会话分页；精确房间号及 live.baidu.com 官方房间/分享链接可直接查询开播与未开播状态，昵称关键词搜索仍待公开网页合同。',
  'baidulive_chat_notice':
      '百度远端聊天尚待接入；目录 audience_count 与房间 online_users 按当前观看人数展示，主播粉丝数单独展示。',
  'baidulive_restricted_notice':
      '该百度直播受付费或访问范围限制，界面保持未知状态，不将其显示成未开播。',
  'baidulive_quality_resolution': '{protocol} {resolution}P · {codec}',
  'baidulive_quality_source': '{protocol} 原始线路 · {codec}',
};

/// easy_localization's `tr(key, namedArgs:)` over [_zh].
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

// 3.x models (the parts the Baidu Live adapter uses) ----------------------------

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

// 3.x's baidu_live_api.dart (imports, `_defaultRequest` and `_readBody` left
// out; the transport must be injected) ---------------------------------------

enum BaiduLiveFailure {
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

final class BaiduLiveException implements Exception {
  const BaiduLiveException(this.kind);

  final BaiduLiveFailure kind;

  @override
  String toString() => 'Baidu Live ${kind.name}';
}

enum BaiduLiveState { live, preview, offline, replay, restricted, unknown }

final class BaiduLiveCategory {
  const BaiduLiveCategory({required this.id, required this.name, required this.channelId});

  final String id;
  final String name;
  final int channelId;
}

final class BaiduLiveVariant {
  BaiduLiveVariant({
    required this.id,
    required this.protocol,
    required this.resolution,
    required this.codec,
    required Iterable<Uri> urls,
  }) : urls = List.unmodifiable(urls);

  final String id;
  final String protocol;
  final int resolution;
  final String codec;
  final List<Uri> urls;
}

final class BaiduLiveRoom {
  BaiduLiveRoom({
    required this.roomId,
    required this.userId,
    required this.nick,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.category,
    required this.currentViewers,
    required this.followers,
    required this.state,
    required Iterable<BaiduLiveVariant> variants,
  }) : variants = List.unmodifiable(variants);

  final String roomId;
  final String userId;
  final String nick;
  final String title;
  final String avatar;
  final String cover;
  final String category;
  final int? currentViewers;
  final int? followers;
  final BaiduLiveState state;
  final List<BaiduLiveVariant> variants;

  BaiduLiveRoom enrich(BaiduLiveRoom known) => BaiduLiveRoom(
    roomId: roomId,
    userId: userId.isEmpty ? known.userId : userId,
    nick: nick == 'Baidu Live' ? known.nick : nick,
    title: title == 'Baidu Live' ? known.title : title,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    cover: cover.isEmpty ? known.cover : cover,
    category: category.isEmpty ? known.category : category,
    currentViewers: currentViewers ?? known.currentViewers,
    followers: followers ?? known.followers,
    state: state,
    variants: variants,
  );
}

final class BaiduLivePage {
  BaiduLivePage({
    required Iterable<BaiduLiveRoom> rooms,
    required Iterable<BaiduLiveCategory> categories,
    required this.sessionId,
    required this.refreshIndex,
    required this.hasMore,
  }) : rooms = List.unmodifiable(rooms),
       categories = List.unmodifiable(categories);

  final List<BaiduLiveRoom> rooms;
  final List<BaiduLiveCategory> categories;
  final String sessionId;
  final int refreshIndex;
  final bool hasMore;
}

typedef BaiduLiveRequest = Future<({int status, String body})> Function(
  Uri uri,
  Map<String, String> headers,
  Map<String, String>? form,
  CancelToken cancel,
);

class BaiduLiveApi {
  BaiduLiveApi({required BaiduLiveRequest request, this.deadline = const Duration(seconds: 20)})
    : _request = request;

  static const String webOrigin = 'https://live.baidu.com';
  static const String detailOrigin = 'https://mbd.baidu.com';
  static const String directoryOrigin = 'https://tiebac.baidu.com';
  static const int responseLimit = 4 * 1024 * 1024;
  static const String _feedSecret = 'CtmXzYPtdE58nCCcvqM0ectyqW3N5rfY';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  static const Map<String, String> apiHeaders = {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Origin': webOrigin,
    'Referer': '$webOrigin/',
  };
  static const List<BaiduLiveCategory> fallbackCategories = [
    BaiduLiveCategory(id: 'rec', name: '推荐', channelId: 570),
    BaiduLiveCategory(id: 'shopping', name: '购物', channelId: 574),
    BaiduLiveCategory(id: 'finance', name: '财经', channelId: 611),
    BaiduLiveCategory(id: 'health', name: '健康', channelId: 612),
    BaiduLiveCategory(id: 'education', name: '教育', channelId: 613),
    BaiduLiveCategory(id: 'news', name: '新闻', channelId: 575),
    BaiduLiveCategory(id: 'leisure', name: '休闲', channelId: 616),
  ];

  static Map<String, String> mediaHeaders(String roomId) => {
    'User-Agent': userAgent,
    'Origin': webOrigin,
    'Referer': BaiduLiveLink.watchUrl(roomId),
  };

  final BaiduLiveRequest _request;
  final Duration deadline;

  Future<T> _scope<T>(CancelToken? caller, Future<T> Function(CancelToken) work) =>
      withRequestCancellation(caller, (transport) async {
        if (transport.isCancelled) throw const BaiduLiveException(BaiduLiveFailure.cancelled);
        try {
          return await Future.any<T>([
            work(transport),
            transport.whenCancel.then<T>((_) => throw const BaiduLiveException(BaiduLiveFailure.cancelled)),
          ]).timeout(deadline);
        } on TimeoutException {
          throw const BaiduLiveException(BaiduLiveFailure.transport);
        } catch (error) {
          if (caller?.isCancelled == true || transport.isCancelled) {
            throw const BaiduLiveException(BaiduLiveFailure.cancelled);
          }
          if (error is BaiduLiveException) rethrow;
          throw const BaiduLiveException(BaiduLiveFailure.transport);
        }
      });

  Future<String> _send(Uri uri, Map<String, String> headers, Map<String, String>? form, CancelToken cancel) async {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw const BaiduLiveException(BaiduLiveFailure.identity);
    }
    final response = await _request(uri, headers, form, cancel);
    _throwStatus(response.status);
    if (response.body.length > responseLimit) throw const BaiduLiveException(BaiduLiveFailure.schema);
    return response.body;
  }

  Future<BaiduLivePage> directory({
    required int page,
    required String tab,
    required int channelId,
    required String sessionId,
    required int refreshIndex,
    required String deviceId,
    CancelToken? cancel,
  }) => _scope(cancel, (token) async {
    if (page < 1 ||
        page > 10000 ||
        !RegExp(r'^[a-z][a-z0-9_]{0,31}$').hasMatch(tab) ||
        channelId < 1 ||
        channelId > 100000 ||
        refreshIndex < 1 ||
        deviceId.length > 96 ||
        !RegExp(r'^pc-[A-Za-z0-9_-]{8,64}$').hasMatch(deviceId)) {
      throw const BaiduLiveException(BaiduLiveFailure.identity);
    }
    final first = page == 1;
    if ((!first && sessionId.isEmpty) || sessionId.length > 128) {
      throw const BaiduLiveException(BaiduLiveFailure.identity);
    }
    final form = <String, String>{
      'appname': 'pclive',
      'sid': '',
      'ua': '320_480_pc_1.0_0',
      'uid': deviceId,
      'timestamp': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'source': 'pclive',
      'resource': first ? 'banner,tab,feed' : 'feed',
      'scene': 'pc_channel',
      'session_id': first ? '' : sessionId,
      'refresh_type': first ? '0' : '1',
      'refresh_index': '$refreshIndex',
      'tab': tab,
      'channel_id': '$channelId',
    };
    form['sign'] = signFeedParameters(form);
    final body = await _send(Uri.parse('$directoryOrigin/livefeed/feed'), apiHeaders, form, token);
    return parseDirectoryJson(_decode(body));
  });

  Future<BaiduLiveRoom> room(String rawRoomId, {bool includeMedia = false, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        final roomId = BaiduLiveLink.parseRoomId(rawRoomId);
        if (roomId == null) throw const BaiduLiveException(BaiduLiveFailure.identity);
        final deviceId = 'pc-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}baidulive';
        final data = jsonEncode({
          'data': {'room_id': roomId, 'device_id': deviceId, 'source_type': 0},
          'replay_slice': 0,
          'nid': '',
          'schemeParams': {
            'src_pre': 'pc',
            'src_suf': 'other',
            'bd_vid': '',
            'share_uid': '',
            'share_cuk': '',
            'share_ecid': '',
            'zb_tag': '',
            'shareTaskInfo': jsonEncode({'room_id': roomId}),
            'share_from': '',
            'ext_params': '',
            'nid': '',
          },
        });
        final uri = Uri.parse('$detailOrigin/searchbox').replace(
          queryParameters: {
            'cmd': '371',
            'action': 'star',
            'service': 'bdbox',
            'osname': 'pc',
            'data': data,
            'ua': '360_740_ANDROID_0',
            'bd_vid': '',
            'uid': deviceId,
            '_': '${DateTime.now().millisecondsSinceEpoch}',
          },
        );
        final result = parseRoomJson(_decode(await _send(uri, apiHeaders, null, token)), expectedRoomId: roomId);
        if (includeMedia && result.state == BaiduLiveState.live && result.variants.isEmpty) {
          throw const BaiduLiveException(BaiduLiveFailure.mediaUnavailable);
        }
        return result;
      });

  static String signFeedParameters(Map<String, String> parameters) {
    final keys = parameters.keys.where((key) => key != 'sign').toList(growable: false)..sort();
    final canonical = keys.map((key) => '$key=${parameters[key]}').join('&');
    return md5.convert(utf8.encode('$canonical&$_feedSecret')).toString();
  }

  static BaiduLivePage parseDirectoryJson(Object? value) {
    final root = _map(value);
    if (_integer(root['errno']) != 0) throw const BaiduLiveException(BaiduLiveFailure.service);
    final data = _map(root['data']);
    final feed = _map(data['feed']);
    if (_integer(feed['inner_errno']) != 0) throw const BaiduLiveException(BaiduLiveFailure.service);
    final rawItems = _list(feed['items']);
    final seen = <String>{};
    final rooms = <BaiduLiveRoom>[];
    for (final value in rawItems) {
      final room = _directoryCard(_map(value));
      if (room != null && seen.add(room.roomId)) rooms.add(room);
    }
    final sessionId = _text(feed['session_id']);
    final refreshIndex = _nonNegative(feed['refresh_index']);
    if (sessionId.isEmpty || refreshIndex == null) throw const BaiduLiveException(BaiduLiveFailure.schema);
    final categories = parseCategoriesJson(data['tab']);
    return BaiduLivePage(
      rooms: rooms,
      categories: categories,
      sessionId: sessionId,
      refreshIndex: refreshIndex,
      hasMore: rawItems.length >= 10,
    );
  }

  static List<BaiduLiveCategory> parseCategoriesJson(Object? value) {
    final tab = _map(value);
    if (tab.isEmpty) return const [];
    if (_integer(tab['inner_errno']) != 0) throw const BaiduLiveException(BaiduLiveFailure.service);
    final categories = <BaiduLiveCategory>[];
    final seen = <String>{};
    for (final value in _list(tab['items'])) {
      final item = _map(value);
      final id = _text(item['type']).toLowerCase();
      final name = _text(item['name']);
      final channelId = _positive(item['channel_id']);
      if (RegExp(r'^[a-z][a-z0-9_]{0,31}$').hasMatch(id) && name.isNotEmpty && channelId != null && seen.add(id)) {
        categories.add(BaiduLiveCategory(id: id, name: name, channelId: channelId));
      }
    }
    return List.unmodifiable(categories);
  }

  static BaiduLiveRoom parseRoomJson(Object? value, {required String expectedRoomId}) {
    final roomId = BaiduLiveLink.parseRoomId(expectedRoomId);
    if (roomId == null) throw const BaiduLiveException(BaiduLiveFailure.identity);
    final root = _map(value);
    if (_integer(root['errno']) != 0) throw const BaiduLiveException(BaiduLiveFailure.service);
    final command = _map(_map(root['data'])['371']);
    if (command.isEmpty) throw const BaiduLiveException(BaiduLiveFailure.missing);
    final error = _integer(command['error_code']);
    if (error != 0) {
      throw BaiduLiveException(error == 1 || error == 4 ? BaiduLiveFailure.missing : BaiduLiveFailure.service);
    }
    final shareUrl = _text(command['share_url']);
    final sharedRoomId = shareUrl.isEmpty ? null : BaiduLiveLink.parseRoomId(shareUrl);
    if (sharedRoomId != null && sharedRoomId != roomId) {
      throw const BaiduLiveException(BaiduLiveFailure.identity);
    }
    final host = _map(command['host']);
    final video = _map(command['video']);
    if (host.isEmpty && video.isEmpty) throw const BaiduLiveException(BaiduLiveFailure.missing);
    final state = _detailState(command);
    final nick = _firstText([host['nick_name'], host['name']], fallback: 'Baidu Live');
    final cover = _map(video['cover']);
    final variants = state == BaiduLiveState.live ? _detailVariants(video, roomId) : const <BaiduLiveVariant>[];
    return BaiduLiveRoom(
      roomId: roomId,
      userId: _text(host['uk']),
      nick: nick,
      title: _firstText([video['title'], nick], fallback: 'Baidu Live'),
      avatar: _image(_map(host['image'])['image_33']),
      cover: _firstImage([cover['cover_100'], cover['vertical_cover']]),
      category: _text(command['category']),
      currentViewers: state == BaiduLiveState.live ? _nonNegative(command['online_users']) : null,
      followers: _nonNegative(command['real_fans_num'] ?? host['fans']),
      state: state,
      variants: variants,
    );
  }

  static Uri? validateMediaUri(String raw, {required String expectedRoomId, required String protocol}) {
    var uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (uri.scheme == 'http' && _allowedMediaHost(host)) uri = uri.replace(scheme: 'https');
    final extension = protocol == 'hls' ? '.m3u8' : '.flv';
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != 443) ||
        !_allowedMediaHost(host) ||
        !uri.path.startsWith('/live/') ||
        !uri.path.toLowerCase().endsWith(extension) ||
        !RegExp('(?:^|_)${RegExp.escape(expectedRoomId)}(?:[-./]|\$)').hasMatch(uri.path)) {
      return null;
    }
    return uri;
  }

  static List<BaiduLiveVariant> _detailVariants(Map<String, Object?> video, String roomId) {
    final grouped = <String, ({String protocol, int resolution, String codec, List<Uri> urls})>{};

    void add(String raw, String protocol, int resolution, String codec) {
      final uri = validateMediaUri(raw, expectedRoomId: roomId, protocol: protocol);
      if (uri == null) return;
      final id = '$protocol:$resolution:$codec';
      final bucket = grouped.putIfAbsent(
        id,
        () => (protocol: protocol, resolution: resolution, codec: codec, urls: <Uri>[]),
      );
      if (!bucket.urls.contains(uri)) bucket.urls.add(uri);
    }

    final clarity = _list(video['url_clarity_list']);
    for (final value in clarity) {
      final item = _map(value);
      final resolution = _positive(item['resolution']) ?? 0;
      final urls = _map(item['urls']);
      add(_text(urls['avc_flv']), 'flv', resolution, 'avc');
      add(_text(urls['flv']), 'flv', resolution, 'avc');
      add(_text(urls['hls']), 'hls', resolution, 'avc');
    }

    final urlList = _list(video['url_list']);
    for (final value in urlList) {
      final item = _map(value);
      final resolution = _positive(item['resolution']) ?? 0;
      for (final rawUrls in _list(item['urls'])) {
        final urls = _map(rawUrls);
        add(_text(urls['flv']), 'flv', resolution, 'avc');
        add(_text(urls['hls']), 'hls', resolution, 'avc');
      }
    }

    final hls = _text(video['live_hls_url']);
    add(hls, 'hls', _resolutionFor(hls, urlList), 'avc');
    if (clarity.isEmpty) {
      add(_text(video['live_flv_url']), 'flv', 0, 'avc');
      add(_text(video['live_flv_url_origin']), 'flv', 0, 'avc');
    }

    final variants =
        grouped.entries
            .where((entry) => entry.value.urls.isNotEmpty)
            .map(
              (entry) => BaiduLiveVariant(
                id: entry.key,
                protocol: entry.value.protocol,
                resolution: entry.value.resolution,
                codec: entry.value.codec,
                urls: entry.value.urls,
              ),
            )
            .toList(growable: false)
          ..sort((left, right) {
            final resolution = right.resolution.compareTo(left.resolution);
            return resolution != 0 ? resolution : left.protocol.compareTo(right.protocol);
          });
    return List.unmodifiable(variants);
  }

  static int _resolutionFor(String raw, List<Object?> urlList) {
    final candidate = Uri.tryParse(raw);
    if (candidate == null) return 0;
    final name = candidate.pathSegments.isEmpty ? '' : candidate.pathSegments.last;
    for (final value in urlList) {
      final item = _map(value);
      final resolution = _positive(item['resolution']);
      if (resolution == null) continue;
      for (final rawUrls in _list(item['urls'])) {
        final hls = Uri.tryParse(_text(_map(rawUrls)['hls']));
        final other = hls == null || hls.pathSegments.isEmpty ? '' : hls.pathSegments.last;
        if (name.isNotEmpty && other == name) return resolution;
      }
    }
    return 0;
  }

  static BaiduLiveRoom? _directoryCard(Map<String, Object?> item) {
    final roomId = BaiduLiveLink.parseRoomId(_text(item['room_id']));
    if (roomId == null) return null;
    final host = _map(item['host']);
    final state = switch (_integer(item['live_status'])) {
      1 => BaiduLiveState.live,
      0 => BaiduLiveState.preview,
      2 => BaiduLiveState.offline,
      3 => BaiduLiveState.replay,
      _ => BaiduLiveState.unknown,
    };
    final nick = _firstText([host['name']], fallback: 'Baidu Live');
    return BaiduLiveRoom(
      roomId: roomId,
      userId: _text(host['uk']),
      nick: nick,
      title: _firstText([item['title'], nick], fallback: 'Baidu Live'),
      avatar: _image(host['avatar']),
      cover: _image(item['cover']),
      category: _firstText([item['live_tag'], _map(item['left_label'])['text']]),
      currentViewers: state == BaiduLiveState.live ? _nonNegative(item['audience_count']) : null,
      followers: null,
      state: state,
      variants: const [],
    );
  }

  static BaiduLiveState _detailState(Map<String, Object?> command) {
    if ((_integer(command['has_pay_service']) ?? 0) > 0 ||
        (_integer(command['is_forbidden_url']) ?? 0) > 0 ||
        (_integer(command['ban_status']) ?? 0) > 0) {
      return BaiduLiveState.restricted;
    }
    return switch (_integer(command['status'])) {
      0 => BaiduLiveState.live,
      -1 || 1 => BaiduLiveState.preview,
      2 || 20 => BaiduLiveState.offline,
      3 => BaiduLiveState.replay,
      _ => BaiduLiveState.unknown,
    };
  }

  static bool _allowedMediaHost(String host) =>
      host == 'hls-live.bdstatic.com' || host == 'flv-live.bdstatic.com' || host.endsWith('.liveshow.bdstatic.com');

  static String _image(Object? value) {
    final raw = _text(value);
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !_allowedImageHost(uri.host.toLowerCase())) {
      return '';
    }
    return uri.toString();
  }

  static bool _allowedImageHost(String host) =>
      host == 'bdstatic.com' ||
      host.endsWith('.bdstatic.com') ||
      host == 'bdimg.com' ||
      host.endsWith('.bdimg.com') ||
      host == 'bcebos.com' ||
      host.endsWith('.bcebos.com');

  static String _firstImage(Iterable<Object?> values) {
    for (final value in values) {
      final image = _image(value);
      if (image.isNotEmpty) return image;
    }
    return '';
  }

  static Object? _decode(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      throw const BaiduLiveException(BaiduLiveFailure.schema);
    }
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map) return const {};
    return value.map((key, entry) => MapEntry('$key', entry));
  }

  static List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

  static String _text(Object? value) => value?.toString().trim() ?? '';

  static String _firstText(Iterable<Object?> values, {String fallback = ''}) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  static int? _integer(Object? value) => switch (value) {
    int number => number,
    num number when number.isFinite && number == number.roundToDouble() => number.toInt(),
    String text => int.tryParse(text.trim()),
    _ => null,
  };

  static int? _nonNegative(Object? value) {
    final number = _integer(value);
    return number != null && number >= 0 ? number : null;
  }

  static int? _positive(Object? value) {
    final number = _integer(value);
    return number != null && number > 0 ? number : null;
  }

  static void _throwStatus(int status) {
    if (status >= 200 && status < 300) return;
    final failure = switch (status) {
      400 || 422 => BaiduLiveFailure.schema,
      401 || 403 || 451 => BaiduLiveFailure.access,
      404 || 410 => BaiduLiveFailure.missing,
      429 => BaiduLiveFailure.rateLimited,
      >= 500 => BaiduLiveFailure.service,
      _ => BaiduLiveFailure.transport,
    };
    throw BaiduLiveException(failure);
  }
}

// 3.x's baidu_live_link.dart, unchanged ---------------------------------------

abstract final class BaiduLiveLink {
  static final RegExp _roomId = RegExp(r'^[1-9]\d{5,19}$');
  static const String _host = 'live.baidu.com';

  static String watchUrl(String raw) => 'https://live.baidu.com/m/room/${requireRoomId(raw)}';

  static String requireRoomId(String raw) {
    final roomId = parseRoomId(raw);
    if (roomId == null) throw const FormatException('Invalid Baidu Live room identity');
    return roomId;
  }

  static String? parseRoomId(String raw) {
    final value = raw.trim();
    if (_roomId.hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != _host ||
        (uri.hasPort && uri.port != 443) ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    if (segments.length == 3 && segments[0] == 'm' && segments[1] == 'room' && _roomId.hasMatch(segments[2])) {
      return segments[2];
    }
    final roomId = uri.queryParameters['room_id']?.trim();
    if (roomId == null || !_roomId.hasMatch(roomId)) return null;
    final path = '/${segments.join('/')}';
    if (path == '/m/media/pclive/pchome/live.html') return roomId;
    if (segments.length == 6 &&
        segments.take(5).join('/') == 'm/media/multipage/liveshow/index' &&
        RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(segments.last)) {
      return roomId;
    }
    return null;
  }
}

// 3.x's baidu_live_site.dart (the LiveSite interfaces and the danmaku left out;
// the API must be injected) ---------------------------------------------------

final class BaiduLiveSite {
  BaiduLiveSite({required BaiduLiveApi api})
    : _api = api,
      _deviceId = 'pc-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}purelivedev';

  final BaiduLiveApi _api;
  final String _deviceId;
  final Map<String, BaiduLiveRoom> _known = {};
  final Map<String, _BaiduDirectorySequence> _sequences = {};
  List<BaiduLiveCategory>? _categories;

  String get id => 'baidulive';

  String get name => i18n('site_baidulive');

  String get directoryNoticeKey => 'baidulive_directory_scope';

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    if (page != 1 || pageSize < 1) return const [];
    final categories = _categories ?? BaiduLiveApi.fallbackCategories;
    return [
      LiveCategory(
        id: id,
        name: name,
        children: categories
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

  BaiduLiveCategory _category(LiveArea? category) {
    final categories = _categories ?? BaiduLiveApi.fallbackCategories;
    if (category == null) return categories.first;
    if (category.platform != id || category.areaType != 'official') {
      throw const BaiduLiveException(BaiduLiveFailure.identity);
    }
    final categoryId = category.areaId?.trim() ?? '';
    return categories.firstWhere(
      (item) => item.id == categoryId,
      orElse: () => throw const BaiduLiveException(BaiduLiveFailure.identity),
    );
  }

  Future<BaiduLivePage> _directory(BaiduLiveCategory category, int page, CancelToken? cancel) async {
    final key = category.id;
    if (page < 1) {
      return BaiduLivePage(rooms: const [], categories: const [], sessionId: '', refreshIndex: 0, hasMore: false);
    }
    if (page == 1) _sequences[key] = _BaiduDirectorySequence();
    final sequence = _sequences[key];
    if (sequence == null || page != sequence.nextPage) {
      return BaiduLivePage(
        rooms: const [],
        categories: const [],
        sessionId: sequence?.sessionId ?? '',
        refreshIndex: sequence?.refreshIndex ?? 0,
        hasMore: false,
      );
    }
    final previousRefreshIndex = sequence.refreshIndex;
    final result = await _api.directory(
      page: page,
      tab: category.id,
      channelId: category.channelId,
      sessionId: sequence.sessionId,
      refreshIndex: page == 1 ? 1 : sequence.refreshIndex + 1,
      deviceId: _deviceId,
      cancel: cancel,
    );
    if (result.categories.isNotEmpty) _categories = result.categories;
    final fresh = result.rooms.where((room) => sequence.seen.add(room.roomId)).toList(growable: false);
    final advanced = page == 1 || result.refreshIndex > previousRefreshIndex;
    final hasMore = result.hasMore && fresh.isNotEmpty && advanced;
    sequence
      ..sessionId = result.sessionId
      ..refreshIndex = result.refreshIndex
      ..nextPage = hasMore ? page + 1 : page;
    _remember(fresh);
    return BaiduLivePage(
      rooms: fresh,
      categories: result.categories,
      sessionId: result.sessionId,
      refreshIndex: result.refreshIndex,
      hasMore: hasMore,
    );
  }

  void _remember(Iterable<BaiduLiveRoom> rooms) {
    for (final room in rooms) {
      _known[room.roomId] = room;
    }
  }

  static LiveRoom _room(BaiduLiveRoom room, {required bool includeMedia}) {
    final online = room.currentViewers?.toString();
    final notice = <String>[
      if (room.state == BaiduLiveState.restricted) i18n('baidulive_restricted_notice'),
      i18n('baidulive_chat_notice'),
    ];
    return LiveRoom(
      platform: 'baidulive',
      roomId: room.roomId,
      userId: room.userId.isEmpty ? room.roomId : room.userId,
      title: room.title,
      nick: room.nick,
      avatar: room.avatar.isEmpty ? room.cover : room.avatar,
      cover: room.cover,
      area: room.category.isEmpty ? i18n('site_baidulive') : room.category,
      link: BaiduLiveLink.watchUrl(room.roomId),
      liveStatus: switch (room.state) {
        BaiduLiveState.live => LiveStatus.live,
        BaiduLiveState.preview || BaiduLiveState.offline || BaiduLiveState.replay => LiveStatus.offline,
        BaiduLiveState.restricted || BaiduLiveState.unknown => LiveStatus.unknown,
      },
      watching: online ?? '',
      onlineViewers: online,
      followers: room.followers?.toString(),
      audienceMetricType: online == null ? AudienceMetricType.unknown : AudienceMetricType.onlineViewers,
      notice: notice.join('\n'),
      httpHeaders: BaiduLiveApi.mediaHeaders(room.roomId),
      data: includeMedia ? room : null,
    );
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final result = await _directory(_category(category), page, cancel);
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
    final roomId = BaiduLiveLink.parseRoomId(keyword.trim());
    if (roomId == null || page != 1 || pageSize < 1) return const [];
    try {
      return [await _detail(roomId, id, includeMedia: false, cancel: cancel)];
    } on BaiduLiveException catch (error) {
      if (error.kind == BaiduLiveFailure.missing) return const [];
      rethrow;
    }
  }

  String _roomId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const BaiduLiveException(BaiduLiveFailure.identity);
    final value = BaiduLiveLink.parseRoomId(roomId);
    if (value == null) throw const BaiduLiveException(BaiduLiveFailure.identity);
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
    final detail = await getRoomDetailForRefresh(roomId: roomId, platform: platform);
    if (detail.effectiveLiveStatus == LiveStatus.unknown) {
      throw const BaiduLiveException(BaiduLiveFailure.access);
    }
    return detail.isLiveNow;
  }

  BaiduLiveRoom _snapshot(LiveRoom detail) {
    final roomId = _roomId(detail.roomId ?? '', detail.platform ?? '');
    final room = detail.data;
    if (room is! BaiduLiveRoom || room.roomId != roomId) {
      throw const BaiduLiveException(BaiduLiveFailure.identity);
    }
    if (room.state != BaiduLiveState.live || room.variants.isEmpty) {
      throw const BaiduLiveException(BaiduLiveFailure.mediaUnavailable);
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
          quality: variant.resolution > 0
              ? i18n(
                  'baidulive_quality_resolution',
                  args: {
                    'protocol': variant.protocol.toUpperCase(),
                    'resolution': '${variant.resolution}',
                    'codec': variant.codec.toUpperCase(),
                  },
                )
              : i18n(
                  'baidulive_quality_source',
                  args: {'protocol': variant.protocol.toUpperCase(), 'codec': variant.codec.toUpperCase()},
                ),
          sort: variant.resolution * 10 + (variant.protocol == 'hls' ? 1 : 2),
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
    throw const BaiduLiveException(BaiduLiveFailure.mediaUnavailable);
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

final class _BaiduDirectorySequence {
  String sessionId = '';
  int refreshIndex = 0;
  int nextPage = 1;
  final Set<String> seen = {};
}
