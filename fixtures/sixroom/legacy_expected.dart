// Writes expected.json for the Six Rooms samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.31-sixroom.md, "样本与 v3 的冻结输出").
//
// The archive has no Six Rooms expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below is 3.x's
// SixRoomApi, SixRoomLink and SixRoomSite, copied from
// legacy/lib/core/site/sixroom/ (archive/v4). 3.x already injected its
// transport (`SixRoomRequest`), so only that is replaced: `_fixtureRequest`
// answers from the samples by method, host, path, query and form fields, with
// the recorded status and body; a request without a sample throws a
// StateError, which 3.x's `_scope` reports as a `transport` failure, and is
// listed under `unmatched`. The streamed body reader (`_defaultRequest`,
// `_readBody`) is left out (it only ran on the network path) and the
// constructors require the transport. `withRequestCancellation`
// (legacy/lib/core/common/request_scope.dart) is copied with Dio's CancelToken
// reduced to a stub. `i18n` returns 3.x's zh.json text of the keys used, with
// easy_localization's `{name}` arguments. 3.x's LiveRoom, LiveArea,
// LiveCategory, LivePlayQuality, LiveDirectoryPage and LivePlayUrlResolution
// are reduced to the parts these classes use (toJson with 3.x's
// HttpHeaderPolicy.normalize). The site keeps its method bodies; `extends
// LiveSite`, `implements`, `@override` and `getDanmaku` (EmptyDanmaku) are
// dropped. The directory clock is injected (3.x's `clock` parameter) so the
// 90 s cache is deterministic. The output format is the legacy harness's
// (`roomProjection`, `errorProjection`, `{generator, value}`); every entry
// point also records its requests with their headers and form fields.
//
// 3.x read its directory from the homepage (`window.__SMARTY_ALL_VARIABLES__`
// `typeList`), searched `search.php`, and read a room from its page (for the
// user id) and the mobile `coop-mobile-inroom.php` POST. The archive recorded
// the search pages and room pages but neither the homepage nor inroom, so
// M4.31 recorded them on 2026-09-28 (`S04-home`, `S05-*`, one moment, with
// 3.x's headers and form). The archive's `S01-list-*` are the mobile list
// API 3.x never called; they have no expected.json.
//
// 3.x parsed the pages with package:html, which the workspace does not depend
// on, so this runs with a throwaway package configuration (3.x's pubspec:
// html ^0.15.4; generated with 0.15.6, as for TwitCasting, niconico,
// Xiaohongshu and Steam). From the repository root:
//
//   d=$(mktemp -d)
//   printf 'name: g\nenvironment:\n  sdk: ^3.9.0\ndependencies:\n  html: 0.15.6\n' > "$d/pubspec.yaml"
//   (cd "$d" && dart pub get --offline)
//   dart --packages="$d/.dart_tool/package_config.json" fixtures/sixroom/legacy_expected.dart
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html_parser;

const _root = 'fixtures/sixroom';

/// The live room of S04-home (its first card), S05-page-live and
/// S05-inroom-live, and its broadcaster.
const _live = '8838';
const _liveUid = '56182128';

/// The offline room of S02-search, S03-room-offline, S05-page-offline and
/// S05-inroom-offline, and its broadcaster.
const _offline = '191111';
const _offlineUid = '63213382';

/// The room of S03-room-notfound (404) and the user of S05-inroom-missing.
const _missing = '99999999999';

/// S05-search-long's keyword: longer than 6.cn's limit (15 characters),
/// shorter than 3.x's (80).
const _longKeyword = 'qzxqzxqzxqzxqzxqzxqz';

const _home = 'S04-home';
const _liveSamples = ['S05-page-live', 'S05-inroom-live'];
const _offlineSamples = ['S05-page-offline', 'S05-inroom-offline'];
const _searchSamples = ['S02-search', 'S02-search-empty', 'S05-search-long'];

/// Inputs for 3.x's `SixRoomLink.parseRoomId` (no requests); the first nine
/// are 3.x's own test cases.
const _links = [
  '8838',
  'https://v.6.cn/8838?from=home',
  'https://m.6.cn/profile/243126861',
  'https://v.6.cn/search.php?key=8838',
  'https://m.v.6.cn/redian/8838',
  'https://v.6.cn.evil.test/8838',
  'https://user@v.6.cn/8838',
  'ftp://v.6.cn/8838',
  '1',
  ' 8838 ',
  '88',
  '0838',
  '123456789012',
  '1234567890123',
  '8838x',
  'http://v.6.cn/8838',
  'https://V.6.CN/8838',
  'HTTPS://v.6.cn/8838',
  'https://m.6.cn/8838',
  'https://v.6.cn:443/8838',
  'http://v.6.cn:80/8838',
  'https://v.6.cn:8443/8838',
  'https://v.6.cn/8838#chat',
  'https://v.6.cn/8838?a=1#',
  'https://v.6.cn/8838/',
  'https://v.6.cn//8838',
  'https://v.6.cn/profile/8838',
  'https://v.6.cn/Profile/8838',
  'https://v.6.cn/profile/8838/more',
  'https://v.6.cn/profile',
  'https://v.6.cn/8838/profile',
  'https://v.6.cn/%38838',
  'https://v.6.cn/%FF',
  'https://6.cn/8838',
  'https://www.6.cn/8838',
  'https://v.6.cn',
  'v.6.cn/8838',
  '',
];

void main() async {
  await _directory();
  await _search();
  await _liveRoom();
  await _offlineRoom();
  await _missingRoom();
  _pages();
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final List<Map<String, Object?>> _requests = [];
final List<String> _unmatched = [];
var _now = DateTime.utc(2026, 9, 28, 13, 50);

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _replay(List<String> samples) {
  _samples = [for (final sample in samples) _meta(sample)];
  _requests.clear();
  _unmatched.clear();
}

bool _sameQuery(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

/// 3.x's `SixRoomRequest` over the samples.
Future<({int status, String body})> _fixtureRequest(
  Uri uri,
  Map<String, String> headers,
  Map<String, String>? form,
  CancelToken cancel,
) async {
  final method = form == null ? 'GET' : 'POST';
  _requests.add({'method': method, 'url': '$uri', 'headers': headers, if (form != null) 'form': form});
  for (final meta in _samples) {
    final request = meta['request'] as Map<String, dynamic>;
    final recorded = Uri.parse(request['url'] as String);
    final recordedForm = request['body'] is String ? Uri.splitQueryString(request['body'] as String) : null;
    if (request['method'] == method &&
        recorded.host == uri.host &&
        recorded.path == uri.path &&
        _sameQuery(recorded.queryParameters, uri.queryParameters) &&
        ((form == null && recordedForm == null) ||
            (form != null && recordedForm != null && _sameQuery(recordedForm, form)))) {
      final status = (meta['response'] as Map)['status'] as int;
      return (status: status, body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync());
    }
  }
  _unmatched.add('$method $uri${form == null ? '' : ' $form'}');
  throw StateError('No recorded sample for $method $uri');
}

SixRoomApi _api() => SixRoomApi(request: _fixtureRequest, clock: () => _now);

SixRoomSite _site() => SixRoomSite(api: _api());

void _write(String sample, String generator, Object? value) {
  final file = File('$_root/$sample/expected.json');
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({'generator': generator, 'value': jsonDecode(jsonEncode(value))})}\n',
  );
  stdout.writeln('wrote $sample');
}

Map<String, dynamic> _errorProjection(Object error) => {
  'throws': switch (error) {
    SixRoomException(:final kind) => 'SixRoomException.${kind.name}',
    TypeError() => 'TypeError',
    FormatException() => 'FormatException',
    ArgumentError() => 'ArgumentError',
    StateError() => 'StateError',
    _ => error.runtimeType.toString(),
  },
  'message': error.toString(),
};

Object? _sync(Object? Function() body) {
  try {
    return body();
  } on Object catch (error) {
    return _errorProjection(error);
  }
}

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

Map<String, Object?> _sixRoomProjection(SixRoomRoom room) => {
  'roomId': room.roomId,
  'userId': room.userId,
  'liveId': room.liveId,
  'nick': room.nick,
  'title': room.title,
  'avatar': room.avatar,
  'cover': room.cover,
  'category': room.category,
  'popularity': room.popularity,
  'followers': room.followers,
  'state': room.state.name,
  'variants': [
    for (final variant in room.variants)
      {
        'id': variant.id,
        'protocol': variant.protocol,
        'resolution': variant.resolution,
        'bitrate': variant.bitrate,
        'urls': [for (final url in variant.urls) '$url'],
      },
  ],
};

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['data'] = switch (room.data) {
      final SixRoomRoom data => _sixRoomProjection(data),
      _ => null,
    };
  json.removeWhere(
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

List<String?> _ids(List<LiveRoom> rooms) => [for (final room in rooms) room.roomId];

Object? _page(LiveDirectoryPage page) => {'rooms': _rooms(page.rooms), 'page': page.page, 'hasMore': page.hasMore};

Object? _pageIds(LiveDirectoryPage page) => {'rooms': _ids(page.rooms), 'page': page.page, 'hasMore': page.hasMore};

Object? _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
];

Object? _resolution(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
};

LiveArea _area(String id, String name) =>
    LiveArea(platform: 'sixroom', areaType: 'official', areaId: id, areaName: name, typeName: '六间房直播');

String _body(String sample) {
  final meta = _meta(sample);
  return File('$_root/$sample/${meta['body']}').readAsStringSync();
}

Map<String, dynamic> _jsonBody(String sample) => jsonDecode(_body(sample)) as Map<String, dynamic>;

/// [html] with the homepage's embedded `typeList` replaced by [rows].
String _withRows(List<Object?> rows) =>
    '<html><script>window.__SMARTY_ALL_VARIABLES__ = ${jsonEncode({'typeList': jsonEncode(rows)})};</script></html>';

// Samples ---------------------------------------------------------------------

/// S04: the categories, the homepage's rooms, the directory of every
/// category with 3.x's local pages and 90 s cache, the recommendations and
/// the link rules.
Future<void> _directory() async {
  _replay([_home]);
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
    'getCategores(pageSize: 3)': await _traced(
      () => _site().getCategores(1, 3),
      (categories) => [for (final area in categories.single.children) area.areaId],
    ),
    'getCategores(page: 2)': await _traced(() => _site().getCategores(2, 30), (categories) => categories.length),
    'getCategores(pageSize: 0)': await _traced(() => _site().getCategores(1, 0), (categories) => categories.length),
    'parseDirectoryHtml': _sync(
      () => [for (final room in SixRoomApi.parseDirectoryHtml(_body(_home))) _sixRoomProjection(room)],
    ),
  };
  // Every page of the whole directory, then each category's pages (ids), on
  // one site: 3.x refreshes the homepage for page 1 of "all" and serves the
  // rest from the snapshot.
  final site = _site();
  final all = <String, Object?>{};
  for (var page = 1; ; page++) {
    final traced = await _traced(() => site.getDirectoryPage(page: page, cancel: CancelToken()), _page);
    all['$page'] = traced;
    final result = traced['result'];
    if (result is! Map || result['hasMore'] != true || page > 40) break;
  }
  value['getDirectoryPage(all)'] = all;
  final categories = <String, Object?>{};
  for (final (id, name) in [
    ('all', '全部'),
    ('song', '歌区'),
    ('dance', '舞区'),
    ('talk', '脱口秀'),
    ('face', '星颜'),
    ('party', '派对'),
  ]) {
    final pages = <String, Object?>{};
    for (var page = 1; ; page++) {
      final traced = await _traced(
        () => site.getDirectoryPage(page: page, category: _area(id, name), cancel: CancelToken()),
        _pageIds,
      );
      pages['$page'] = traced;
      final result = traced['result'];
      if (result is! Map || result['hasMore'] != true || page > 40) break;
    }
    categories[id] = pages;
  }
  value['getDirectoryPage(category)'] = categories;
  value['getDirectoryPage(song page 1)'] = await _traced(
    () => site.getDirectoryPage(page: 1, category: _area('song', '歌区'), cancel: CancelToken()),
    _page,
  );
  value['getDirectoryPage(edge)'] = {
    'page 0': await _traced(() => _site().getDirectoryPage(page: 0, cancel: CancelToken()), _pageIds),
    'page 0 other platform': await _traced(
      () => _site().getDirectoryPage(
        page: 0,
        category: LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'song'),
        cancel: CancelToken(),
      ),
      _pageIds,
    ),
    'page 10001': await _traced(() => _site().getDirectoryPage(page: 10001, cancel: CancelToken()), _pageIds),
    'page 10000': await _traced(() => _site().getDirectoryPage(page: 10000, cancel: CancelToken()), _pageIds),
    'other platform': await _traced(
      () => _site().getDirectoryPage(
        category: LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'song'),
        cancel: CancelToken(),
      ),
      _pageIds,
    ),
    'other areaType': await _traced(
      () => _site().getDirectoryPage(
        category: LiveArea(platform: 'sixroom', areaType: 'u0', areaId: 'song'),
        cancel: CancelToken(),
      ),
      _pageIds,
    ),
    'unknown area': await _traced(
      () => _site().getDirectoryPage(category: _area('u10', '星颜'), cancel: CancelToken()),
      _pageIds,
    ),
    'area id with spaces': await _traced(
      () => _site().getDirectoryPage(category: _area(' song ', '歌区'), cancel: CancelToken()),
      _pageIds,
    ),
  };
  // 3.x's 90 s snapshot: category pages and later pages reuse it; page 1 of
  // "all" (and of the recommendations) always refreshes.
  _now = DateTime.utc(2026, 9, 28, 13, 50);
  final cached = _site();
  final cache = <String, Object?>{};
  Future<void> step(String name, Future<Object?> Function() call) async {
    cache[name] = await _traced(call, (result) => result);
  }

  await step('song page 1 (empty cache)', () async => _ids((await cached.getCategoryRooms(_area('song', '歌区')))));
  await step('dance page 1', () async => _ids(await cached.getCategoryRooms(_area('dance', '舞区'))));
  await step('all page 2', () async => _ids((await cached.getDirectoryPage(page: 2)).rooms));
  await step('all page 1', () async => _ids((await cached.getDirectoryPage(page: 1)).rooms));
  _now = _now.add(const Duration(seconds: 89));
  await step('+89 s talk page 1', () async => _ids(await cached.getCategoryRooms(_area('talk', '脱口秀'))));
  _now = _now.add(const Duration(seconds: 1));
  await step('+90 s talk page 1', () async => _ids(await cached.getCategoryRooms(_area('talk', '脱口秀'))));
  await step('recommend page 2', () async => _ids(await cached.getRecommendRooms(page: 2)));
  await step('recommend page 1', () async => _ids(await cached.getRecommendRooms(page: 1)));
  _now = _now.subtract(const Duration(seconds: 1));
  await step('clock back 1 s: party page 1', () async => _ids(await cached.getCategoryRooms(_area('party', '派对'))));
  _now = DateTime.utc(2026, 9, 28, 13, 50);
  value['cache'] = cache;
  value['getRecommendRooms'] = {
    for (final (page, size) in [(1, 30), (1, 3), (2, 20), (1, 0), (0, 30), (1, 101), (15, 30), (16, 30)])
      'page $page size $size': await _traced(() => _site().getRecommendRooms(page: page, pageSize: size), _ids),
  };
  value['getRecommendRooms(page 1 size 3)'] = await _traced(
    () => _site().getRecommendRooms(page: 1, pageSize: 3),
    _rooms,
  );
  value['getCategoryRooms'] = {
    for (final (id, name) in [('song', '歌区'), ('face', '星颜'), ('party', '派对')])
      '$id page 1 size 5': await _traced(() => _site().getCategoryRooms(_area(id, name), page: 1, pageSize: 5), _rooms),
    'party page 2 size 20': await _traced(
      () => _site().getCategoryRooms(_area('party', '派对'), page: 2, pageSize: 20),
      _ids,
    ),
    'otherPlatform': await _traced(
      () => _site().getCategoryRooms(LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'song')),
      _ids,
    ),
  };
  final rows = jsonDecode(SixRoomApi._decodeEmbeddedRoot(_body(_home))['typeList'] as String) as List;
  final first = Map<String, Object?>.from(rows.first as Map);
  Object? parseRows(List<Object?> changed) =>
      _sync(() => [for (final room in SixRoomApi.parseDirectoryHtml(_withRows(changed))) _sixRoomProjection(room)]);
  value['parseDirectoryHtml(variants)'] = {
    'typeList as a list': _sync(
      () => SixRoomApi.parseDirectoryHtml(
        '<script>window.__SMARTY_ALL_VARIABLES__ = ${jsonEncode({'typeList': rows.take(2).toList()})};</script>',
      ).length,
    ),
    'no marker': _sync(() => SixRoomApi.parseDirectoryHtml('<html></html>')),
    'typeList missing': _sync(
      () => SixRoomApi.parseDirectoryHtml('<script>window.__SMARTY_ALL_VARIABLES__ = {"x":1};</script>'),
    ),
    'typeList not JSON': _sync(
      () => SixRoomApi.parseDirectoryHtml('<script>window.__SMARTY_ALL_VARIABLES__ = {"typeList":"[x"};</script>'),
    ),
    'unterminated': _sync(
      () => SixRoomApi.parseDirectoryHtml('<script>window.__SMARTY_ALL_VARIABLES__ = {"typeList":"[]"'),
    ),
    'braces in strings': parseRows([
      {...first, 'livetitle': 'a } { "b" \\ c'},
    ]),
    'empty': parseRows([]),
    'duplicate rid': parseRows([
      first,
      {...first, 'username': 'second'},
    ]),
    'bad rid': parseRows([
      {...first, 'rid': '0123'},
      {...first, 'rid': 8838},
      {...first, 'rid': '1'},
    ]),
    'bad uid': parseRows([
      {...first, 'uid': ''},
      {...first, 'rid': '8839', 'uid': '1'},
    ]),
    'numbers': parseRows([
      {...first, 'rid': 8838, 'uid': 56182128, 'liveid': 222, 'count': 23104},
    ]),
    'lid': parseRows([
      {...(Map.of(first)..remove('liveid')), 'lid': '333'},
    ]),
    'titles': parseRows([
      {...first, 'rid': '1001', 'livetitle': '  a   title ', 'userMood': 'mood'},
      {...first, 'rid': '1002', 'livetitle': '', 'userMood': 'mood'},
      {...first, 'rid': '1003', 'livetitle': '', 'userMood': ''},
      {...first, 'rid': '1004', 'livetitle': '', 'userMood': '', 'username': ''},
      {...first, 'rid': '1005', 'livetitle': null, 'userMood': null, 'username': null},
    ]),
    'images': parseRows([
      {...first, 'rid': '1001', 'pospic': '', 'pic': 'https://vi0.6rooms.com/live/p.jpg'},
      {...first, 'rid': '1002', 'pospic': '', 'pic': '', 'pospic_sp': 'https://vi2.6rooms.com/live/sp.jpg'},
      {...first, 'rid': '1003', 'pospic': 'http://vi0.6rooms.com/live/h.jpg', 'picuser': '//vi1.6rooms.com/live/a.jpg'},
      {...first, 'rid': '1004', 'pospic': 'https://example.com/x.jpg', 'pic': '', 'pospic_sp': '', 'picuser': ''},
      {...first, 'rid': '1005', 'pospic': 'https://vi0.xiu123.cn/x.jpg', 'picuser': 'https://6.cn/a.jpg'},
      {...first, 'rid': '1006', 'pospic': 'https://vi0.6rooms.com:8443/x.jpg', 'picuser': 'https://u@vi1.6rooms.com/a'},
      {...first, 'rid': '1007', 'pospic': 'https://vi0.6rooms.com/x.jpg#f', 'picuser': 'ftp://vi1.6rooms.com/a'},
      {...first, 'rid': '1008', 'pospic': 'https://evil6rooms.com/x.jpg', 'picuser': 'https://vi1.6ROOMS.com/a'},
    ]),
    'count': parseRows([
      {...first, 'rid': '1001', 'count': '1,234'},
      {...first, 'rid': '1002', 'count': -5},
      {...first, 'rid': '1003', 'count': '-5'},
      {...first, 'rid': '1004', 'count': 3.7},
      {...first, 'rid': '1005', 'count': 'x'},
      {...first, 'rid': '1006', 'count': null},
      {...first, 'rid': '1007', 'count': ''},
    ]),
    'area': parseRows([
      {...first, 'rid': '1001', 'anchor_area': '  舞区 '},
      {...first, 'rid': '1002', 'anchor_area': null},
    ]),
    'not a map': parseRows([1, 'x', null, first]),
  };
  value['SixRoomLink.parseRoomId'] = {for (final link in _links) link: _sync(() => SixRoomLink.parseRoomId(link))};
  value['SixRoomLink.watchUrl'] = {
    for (final id in [_live, ' $_live ', 'https://m.6.cn/profile/$_live', '1'])
      id: _sync(() => SixRoomLink.watchUrl(id)),
  };
  value['SixRoomApi.mediaHeaders'] = SixRoomApi.mediaHeaders(_live);
  value['directoryNoticeKey'] = _site().directoryNoticeKey;
  value['name'] = _site().name;
  _write(
    _home,
    'SixRoomSite.getCategores + getDirectoryPage + getRecommendRooms + getCategoryRooms + '
    'SixRoomApi.parseDirectoryHtml + mediaHeaders + SixRoomLink',
    value,
  );
}

/// S02 and S05-search-long: 3.x's search pages and keyword lookups, with the
/// exact room ids (S05 and S03-room-notfound) 3.x looked up as rooms.
Future<void> _search() async {
  _replay([..._searchSamples, ..._liveSamples, 'S03-room-notfound']);
  Object? parse(String html) =>
      _sync(() => [for (final room in SixRoomApi.parseSearchHtml(html)) _sixRoomProjection(room)]);
  final keywords = <String, Object?>{};
  for (final (keyword, page, size) in [
    ('诺', 1, 30),
    (' 诺 ', 1, 30),
    ('诺', 1, 3),
    ('诺', 2, 30),
    ('诺', 0, 30),
    ('诺', 1, 0),
    ('诺', 1, 100),
    ('诺', 1, 101),
    ('', 1, 30),
    ('   ', 1, 30),
    ('qzxqzx', 1, 30),
    (_longKeyword, 1, 30),
    ('x' * 81, 1, 30),
    (_live, 1, 30),
    (' $_live ', 1, 30),
    ('https://v.6.cn/$_live', 1, 30),
    ('https://m.6.cn/profile/$_live', 1, 30),
    (_live, 2, 30),
    (_missing, 1, 30),
  ]) {
    keywords['"$keyword" page $page size $size'] = await _traced(
      () => _site().searchRoomsCancellable(keyword, page: page, pageSize: size, cancel: CancelToken()),
      _rooms,
    );
  }
  final search = _body('S02-search');
  _write(
    'S02-search',
    'SixRoomSite.searchRoomsCancellable (with S02-search-empty, S05-search-long, S05-page-live, '
        'S05-inroom-live, S03-room-notfound) + SixRoomApi.parseSearchHtml',
    {
      'parseSearchHtml': parse(search),
      'parseSearchHtml(variants)': {
        'no result block': parse('<html><body><div class="x"></div></body></html>'),
        'remind page': parse('<div class="remind"><div class="rcontent">x</div></div>'),
        'duplicate and invalid': parse('''
<div class="page-search-user"><ul class="search-user">
<li data-uid="31648937"><a class="user-box" href="/profile/1890"><div class="pic"><img src="//vi0.6rooms.com/live/a.jpg"></div><div class="alias"> 小荷叶   加油 </div></a></li>
<li data-uid="31648937"><a class="user-box" href="/1890"><div class="alias">again</div></a></li>
<li data-uid="1"><a class="user-box" href="/1891"><div class="alias">bad uid</div></a></li>
<li data-uid="31648938"><a class="user-box" href="/search.php"><div class="alias">bad link</div></a></li>
<li data-uid="31648939"><a class="user-box" href="https://m.6.cn/1892"><div class="alias"></div></a></li>
<li data-uid="31648940"><a class="user-box" href="https://example.com/1893"><div class="alias">other host</div></a></li>
<li data-uid="31648941"><a class="other" href="/1894"><div class="alias">no user-box</div></a></li>
<li><a class="user-box" href="/1895"><div class="alias">no uid</div></a></li>
</ul><ul class="other"><li data-uid="31648942"><a class="user-box" href="/1896"></a></li></ul></div>
'''),
      },
      'searchRooms': keywords,
    },
  );
  _write('S02-search-empty', 'SixRoomApi.parseSearchHtml', {'parseSearchHtml': parse(_body('S02-search-empty'))});
  _write('S05-search-long', 'SixRoomApi.parseSearchHtml', {'parseSearchHtml': parse(_body('S05-search-long'))});
}

/// A room at every depth on [site], its live status, qualities and URLs,
/// with every request.
Future<Map<String, Object?>> _roomCalls(String roomId, Future<SixRoomSite> Function() site) async {
  final value = <String, Object?>{};
  for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
    final current = await site();
    value[depth] = await _traced(
      () => switch (depth) {
        'getRoomDetail' => current.getRoomDetail(roomId: roomId, platform: 'sixroom'),
        'getRoomDetailForRefresh' => current.getRoomDetailForRefresh(roomId: roomId, platform: 'sixroom'),
        _ => current.getRoomDetailForRecording(roomId: roomId, platform: 'sixroom'),
      },
      _roomProjection,
    );
  }
  final status = await site();
  value['getLiveStatus'] = await _traced(
    () => status.getLiveStatus(platform: 'sixroom', roomId: roomId),
    (live) => live,
  );
  final source = LivePlayQuality(id: 'flv:source', quality: 'FLV 原始线路');
  for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh']) {
    final current = await site();
    final LiveRoom detail;
    try {
      detail = depth == 'getRoomDetail'
          ? await current.getRoomDetail(roomId: roomId, platform: 'sixroom')
          : await current.getRoomDetailForRefresh(roomId: roomId, platform: 'sixroom');
    } on Object catch (error) {
      value['$depth → streams'] = _errorProjection(error);
      continue;
    }
    value['$depth → streams'] = {
      'getPlayQualites': await _traced(() => current.getPlayQualites(detail: detail), _qualities),
      'resolvePlayUrlsRaw': await _traced(
        () => current.resolvePlayUrlsRaw(detail: detail, quality: source),
        _resolution,
      ),
      'resolvePlayUrlsForRecoveryRaw': await _traced(
        () => current.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: source),
        _resolution,
      ),
      'getPlayUrls': await _traced(() => current.getPlayUrls(detail: detail, quality: source), (urls) => urls),
      'otherQuality': await _traced(
        () => current.resolvePlayUrlsRaw(
          detail: detail,
          quality: LivePlayQuality(id: 'source', quality: 'x'),
        ),
        _resolution,
      ),
    };
  }
  return value;
}

/// The first page of the directory, untraced: 3.x's site then knows every
/// listed broadcaster's user id and card.
Future<SixRoomSite> _afterDirectory() async {
  final site = _site();
  await site.getDirectoryPage(page: 1, cancel: CancelToken());
  return site;
}

/// A search for 诺 (S02-search), untraced: 3.x's site then knows the offline
/// broadcaster's user id and avatar.
Future<SixRoomSite> _afterSearch() async {
  final site = _site();
  await site.searchRooms('诺');
  return site;
}

/// S05 live: the room cold (3.x read the user id from the room page) and
/// after the directory (3.x knew it), the streams, and what 3.x's detail
/// is when only the user id is known (`SixRoomApi.room` with `knownUserId`).
Future<void> _liveRoom() async {
  _replay([..._liveSamples, _home]);
  final value = <String, Object?>{
    'cold': await _roomCalls(_live, () async => _site()),
    'after the directory': await _roomCalls(_live, _afterDirectory),
    'knownUserId': {
      for (final media in [true, false])
        'includeMedia $media': await _traced(() async {
          final room = await _api().room(_live, knownUserId: _liveUid, includeMedia: media);
          return SixRoomSite._room(room, includeMedia: media);
        }, _roomProjection),
    },
    'knownUserId (bad)': await _traced(
      () => _api().room(_live, knownUserId: '1', includeMedia: false),
      _sixRoomProjection,
    ),
    'getRoomDetail(link)': await _traced(
      () async =>
          (await _afterDirectory()).getRoomDetail(roomId: 'https://v.6.cn/$_live?from=home', platform: 'sixroom'),
      _roomProjection,
    ),
    'getRoomDetail(other platform)': await _traced(
      () => _site().getRoomDetail(roomId: _live, platform: 'bilibili'),
      _roomProjection,
    ),
    'getRoomDetail(not an id)': await _traced(
      () => _site().getRoomDetail(roomId: 'abc', platform: 'sixroom'),
      _roomProjection,
    ),
    'directory card after the room': await _traced(() async {
      final site = await _afterDirectory();
      await site.getRoomDetail(roomId: _live, platform: 'sixroom');
      return (await site.getDirectoryPage(page: 1, cancel: CancelToken())).rooms.take(1).toList();
    }, _rooms),
    ..._inroomLive(),
  };
  _write(
    'S05-inroom-live',
    'SixRoomSite room calls, cold and after getDirectoryPage (with S05-page-live, S04-home) + SixRoomApi.room '
        '+ parseRoomJson + mediaUri',
    value,
  );
}

/// S05 offline: the room cold and after the search (S02-search knows the
/// broadcaster).
Future<void> _offlineRoom() async {
  _replay([..._offlineSamples, 'S02-search']);
  _write(
    'S05-inroom-offline',
    'SixRoomSite room calls, cold and after searchRooms (with S05-page-offline, '
        'S02-search) + SixRoomApi.room + parseRoomJson',
    {
      'cold': await _roomCalls(_offline, () async => _site()),
      'after the search': await _roomCalls(_offline, _afterSearch),
      'knownUserId': await _traced(() async {
        final room = await _api().room(_offline, knownUserId: _offlineUid);
        return SixRoomSite._room(room, includeMedia: true);
      }, _roomProjection),
      'parseRoomJson': {
        'recorded': _parseInroom(_jsonBody('S05-inroom-offline'), roomId: _offline, userId: _offlineUid),
        'other user asked': _parseInroom(_jsonBody('S05-inroom-offline'), roomId: _offline, userId: _liveUid),
      },
    },
  );
}

/// S03-room-notfound (404) and S05-inroom-missing (flag 402).
Future<void> _missingRoom() async {
  _replay(['S03-room-notfound', 'S05-inroom-missing']);
  _write('S03-room-notfound', 'SixRoomSite.getRoomDetail + getLiveStatus + searchRooms', {
    'getRoomDetail': await _traced(() => _site().getRoomDetail(roomId: _missing, platform: 'sixroom'), _roomProjection),
    'getLiveStatus': await _traced(() => _site().getLiveStatus(platform: 'sixroom', roomId: _missing), (live) => live),
    'searchRooms': await _traced(() => _site().searchRooms(_missing), _rooms),
    'parseRoomUserIdHtml': _sync(() => SixRoomApi.parseRoomUserIdHtml(_body('S03-room-notfound'), _missing)),
  });
  _write('S05-inroom-missing', 'SixRoomApi.room (knownUserId) + parseRoomJson', {
    'room': await _traced(() => _api().room(_missing, knownUserId: _missing), _sixRoomProjection),
    'parseRoomJson': _sync(
      () => SixRoomApi.parseRoomJson(_body('S05-inroom-missing'), expectedRoomId: _missing, expectedUserId: _missing),
    ),
  });
}

/// The room pages: 3.x's user id lookup (`parseRoomUserIdHtml`) on every
/// recorded page and on changed copies.
void _pages() {
  Object? parse(String html, String roomId) => _sync(() => SixRoomApi.parseRoomUserIdHtml(html, roomId));
  final live = _body('S05-page-live');
  final quoted = live.replaceFirst('roomid: $_live,', "roomid: '$_live',");
  _write('S05-page-live', 'SixRoomApi.parseRoomUserIdHtml', {
    'recorded': parse(live, _live),
    'roomid quoted (3.x format)': parse(quoted, _live),
    'roomid quoted, double quotes': parse(live.replaceFirst('roomid: $_live,', 'roomid: "$_live",'), _live),
    'roomid quoted, other room asked': parse(quoted, '8839'),
    'roomid quoted, link asked': parse(quoted, 'https://v.6.cn/$_live'),
    'roomid quoted, bad id asked': parse(quoted, 'abc'),
    'roomid quoted, canonical of another room': parse(
      quoted.replaceFirst('href="https://v.6.cn/$_live"', 'href="https://v.6.cn/8839"'),
      _live,
    ),
    'roomid quoted, no canonical': parse(quoted.replaceFirst('rel="canonical"', 'rel="x"'), _live),
    'roomid quoted, rid of another room': parse(quoted.replaceFirst("roomid: '$_live'", "roomid: '8839'"), _live),
    'no rid': parse(quoted.replaceFirst("rid: '$_liveUid'", "xid: '$_liveUid'"), _live),
    'unquoted roomid with more digits': parse(live.replaceFirst('roomid: $_live,', 'roomid: ${_live}9,'), _live),
    'remind page': parse(_body('S05-search-long'), _live),
    'short page': parse('<html><head></head><body>x</body></html>', _live),
    "3.x's test page": parse('''
<html><head><link rel="canonical" href="https://v.6.cn/8838"></head><body><script>
var room = {rid: '56182128', roomid: '8838', liveid: '222415076'};
</script></body></html>
''', '8838'),
  });
  _write('S05-page-offline', 'SixRoomApi.parseRoomUserIdHtml', {
    'recorded': parse(_body('S05-page-offline'), _offline),
    'roomid quoted (3.x format)': parse(
      _body('S05-page-offline').replaceFirst('roomid: $_offline,', "roomid: '$_offline',"),
      _offline,
    ),
  });
  _write('S03-room-live', 'SixRoomApi.parseRoomUserIdHtml', {'recorded': parse(_body('S03-room-live'), '16066')});
  _write('S03-room-offline', 'SixRoomApi.parseRoomUserIdHtml', {
    'recorded': parse(_body('S03-room-offline'), _offline),
  });
}

/// 3.x's `parseRoomJson` of [json] (an answer, or its text).
Object? _parseInroom(Object? json, {String roomId = _live, String userId = _liveUid, bool includeMedia = true}) =>
    _sync(
      () => _sixRoomProjection(
        SixRoomApi.parseRoomJson(
          json is String ? json : jsonEncode(json),
          expectedRoomId: roomId,
          expectedUserId: userId,
          includeMedia: includeMedia,
        ),
      ),
    );

/// The live inroom answer: 3.x's `parseRoomJson` of it and of changed
/// copies, and `mediaUri`.
Map<String, Object?> _inroomLive() {
  const parse = _parseInroom;
  Map<String, dynamic> live() => _jsonBody('S05-inroom-live');
  Map<String, dynamic> content(Map<String, dynamic> root) => root['content'] as Map<String, dynamic>;
  Map<String, dynamic> section(Map<String, dynamic> root, String name) => content(root)[name] as Map<String, dynamic>;
  Map<String, dynamic> change(void Function(Map<String, dynamic> root) edit) {
    final root = live();
    edit(root);
    return root;
  }

  final liveInfo = section(live(), 'liveinfo');
  final flvTitle = liveInfo['flvtitle'] as String;
  final liveId = liveInfo['id'] as String;
  final value = <String, Object?>{
    'recorded': parse(live()),
    'recorded (includeMedia false)': parse(live(), includeMedia: false),
    'other room asked': parse(live(), roomId: '8839'),
    'other user asked': parse(live(), userId: '56182129'),
    'link asked': parse(live(), roomId: 'https://v.6.cn/$_live'),
    'bad user asked': parse(live(), userId: '1'),
    'flag 402': parse(change((root) => root['flag'] = '402')),
    'flag missing': parse(change((root) => root.remove('flag'))),
    'flag number': parse(change((root) => root['flag'] = 1)),
    'no content': parse(change((root) => root['content'] = 'x')),
    'no roominfo': parse(change((root) => content(root).remove('roominfo'))),
    'no liveinfo': parse(change((root) => content(root).remove('liveinfo'))),
    'no roomParamInfo': parse(change((root) => content(root).remove('roomParamInfo'))),
    'roominfo without id': parse(change((root) => section(root, 'roominfo').remove('id'))),
    'roominfo of another room': parse(change((root) => section(root, 'roominfo')['rid'] = '8839')),
    'private (1)': parse(change((root) => content(root)['isPriveRoom'] = 1)),
    'private ("1")': parse(change((root) => content(root)['isPriveRoom'] = '1')),
    'private (true)': parse(change((root) => content(root)['isPriveRoom'] = true)),
    'private ("0")': parse(change((root) => content(root)['isPriveRoom'] = '0')),
    'black screen': parse(change((root) => content(root)['blackScreenInfo'] = {'msg': ' 黑屏 ', 'endtm': 1})),
    'black screen not a map': parse(change((root) => content(root)['blackScreenInfo'] = 'x')),
    'no live id': parse(change((root) => section(root, 'liveinfo').remove('id'))),
    'no stream name': parse(change((root) => section(root, 'liveinfo')['flvtitle'] = '')),
    'stream name of another user': parse(change((root) => section(root, 'liveinfo')['flvtitle'] = 'v99999999-$liveId')),
    'stream name -many': parse(change((root) => section(root, 'liveinfo')['flvtitle'] = '$flvTitle-many')),
    'stream name with a path': parse(change((root) => section(root, 'liveinfo')['flvtitle'] = '$flvTitle/x')),
    'live id not digits': parse(
      change(
        (root) => section(root, 'liveinfo')
          ..['id'] = 'x$liveId'
          ..['flvtitle'] = 'v$_liveUid-x$liveId',
      ),
    ),
    'no stream info': parse(change((root) => section(root, 'liveinfo').remove('content'))),
    'bitrate instead of videoBitrate': parse(
      change((root) {
        final lanes = section(root, 'liveinfo')['content'] as Map<String, dynamic>;
        final info =
            ((lanes['1'] as Map<String, dynamic>)['streamInfo'] as Map<String, dynamic>)[flvTitle]
                as Map<String, dynamic>;
        info['bitrate'] = info.remove('videoBitrate');
      }),
    ),
    'stream info in another lane': parse(
      change((root) {
        final lanes = section(root, 'liveinfo')['content'] as Map<String, dynamic>;
        lanes['2'] = lanes.remove('1');
      }),
    ),
    'title': parse(change((root) => section(root, 'liveinfo')['title'] = '  今晚   唱歌 ')),
    'userMood': parse(change((root) => section(root, 'roominfo')['userMood'] = '签名')),
    'no alias': parse(change((root) => section(root, 'roominfo')['alias'] = '')),
    'no alias, no title': parse(
      change((root) {
        section(root, 'roominfo')['alias'] = null;
        section(root, 'liveinfo')['title'] = null;
      }),
    ),
    'avatars': {
      for (final (field, url) in [
        ('headPicUrl', 'https://vi1.6rooms.com/live/a.jpg'),
        ('headPicUrl', 'http://vi1.6rooms.com/live/a.jpg'),
        ('headPicUrl', '//vi1.6rooms.com/live/a.jpg'),
        ('headPicUrl', 'https://example.com/a.jpg'),
        ('headPicUrl', 'https://vi1.xiu123.cn/a.jpg'),
        ('picuser', 'https://vi1.6rooms.com/live/p.jpg'),
      ])
        '$field $url': parse(change((root) => section(root, 'roominfo')[field] = url)),
    },
    'covers': {
      'no spredPic': parse(change((root) => section(root, 'liveinfo').remove('spredPic'))),
      'no spredPic, no pospic': parse(
        change(
          (root) => section(root, 'liveinfo')
            ..remove('spredPic')
            ..remove('pospic'),
        ),
      ),
      'only pic': parse(
        change(
          (root) => section(root, 'liveinfo')
            ..remove('spredPic')
            ..remove('pospic')
            ..['largepic'] = ''
            ..['pic'] = 'https://vi0.6rooms.com/live/pic.jpg',
        ),
      ),
      'no image': parse(
        change(
          (root) => section(root, 'liveinfo')
            ..remove('spredPic')
            ..remove('pospic')
            ..['largepic'] = ''
            ..['pic'] = '',
        ),
      ),
    },
    'category': {
      'no anchor_area': parse(change((root) => section(root, 'roominfo')['anchor_area'] = '')),
      'neither': parse(
        change(
          (root) => section(root, 'roominfo')
            ..['anchor_area'] = ''
            ..['rtypename'] = '',
        ),
      ),
    },
    'fans_num': {
      for (final fans in ['1,234', -1, 3.9, null, 'x', '12'])
        '$fans': parse(change((root) => section(root, 'roomParamInfo')['fans_num'] = fans)),
    },
    'not JSON': parse('<html>'),
    'a list': parse('[1]'),
  };
  return {
    'parseRoomJson': value,
    'mediaUri': {
      for (final (userId, liveId, name) in [
        (_liveUid, liveId, flvTitle),
        (_liveUid, liveId, '$flvTitle-many'),
        (_liveUid, liveId, 'v99999999-$liveId'),
        (_liveUid, liveId, '$flvTitle-other'),
        ('1', liveId, 'v1-$liveId'),
        (_liveUid, '', 'v$_liveUid-'),
        (_liveUid, liveId, 'v$_liveUid-$liveId.flv'),
      ])
        '$userId $liveId $name': _sync(
          () => SixRoomApi.mediaUri(userId: userId, liveId: liveId, flvTitle: name)?.toString(),
        ),
    },
  };
}

// 3.x models (the parts the Six Rooms classes use) ----------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

/// Dio's CancelToken, reduced to what 3.x's Six Rooms classes use.
class CancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancel => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// 3.x's request_scope.dart.
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

/// 3.x's zh.json text of the keys used; `{name}` arguments as
/// easy_localization's `namedArgs`.
String i18n(String key, {Map<String, String>? args}) {
  var text =
      const {
        'site_sixroom': '六间房直播',
        'sixroom_chat_notice': '六间房远端聊天尚待接入；大厅 count 保留为平台热度，不标记为唯一并发人数，主播粉丝数单独展示。',
        'sixroom_restricted_notice': '该六间房直播受私密房或黑屏访问条件限制，界面保持未知状态，不将其显示成未开播。',
        'sixroom_quality_source': 'FLV 原始线路',
        'sixroom_quality_source_detail': 'FLV 原始线路 · {detail}',
      }[key] ??
      (throw StateError('No zh.json text for $key'));
  for (final MapEntry(:key, :value) in (args ?? const <String, String>{}).entries) {
    text = text.replaceAll('{$key}', value);
  }
  return text;
}

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

// 3.x's Six Rooms adapter (legacy/lib/core/site/sixroom/) ---------------------
//
// Unchanged apart from the model names above and the transport: no Dio, so
// `CancelToken` is the stub above, and `_defaultRequest` / `_readBody` are
// left out (the constructors require the transport).

// sixroom_link.dart

abstract final class SixRoomLink {
  static final RegExp _roomId = RegExp(r'^[1-9]\d{1,11}$');
  static const Set<String> _hosts = {'v.6.cn', 'm.6.cn'};

  static String watchUrl(String raw) => 'https://v.6.cn/${requireRoomId(raw)}';

  static String requireRoomId(String raw) {
    final value = parseRoomId(raw);
    if (value == null) throw const FormatException('Invalid Six Rooms room identity');
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
    if (segments.length == 2 && segments.first.toLowerCase() == 'profile' && _roomId.hasMatch(segments.last)) {
      return segments.last;
    }
    return null;
  }
}

// sixroom_api.dart

enum SixRoomFailure { transport, access, missing, rateLimited, service, schema, identity, cancelled, mediaUnavailable }

final class SixRoomException implements Exception {
  const SixRoomException(this.kind);

  final SixRoomFailure kind;

  @override
  String toString() => 'Six Rooms ${kind.name}';
}

enum SixRoomState { live, offline, restricted, unknown }

final class SixRoomCategory {
  const SixRoomCategory({required this.id, required this.name, this.area});

  final String id;
  final String name;
  final String? area;
}

final class SixRoomVariant {
  SixRoomVariant({
    required this.id,
    required this.protocol,
    required this.resolution,
    required this.bitrate,
    required Iterable<Uri> urls,
  }) : urls = List.unmodifiable(urls);

  final String id;
  final String protocol;
  final String resolution;
  final int? bitrate;
  final List<Uri> urls;
}

final class SixRoomRoom {
  SixRoomRoom({
    required this.roomId,
    required this.userId,
    required this.liveId,
    required this.nick,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.category,
    required this.popularity,
    required this.followers,
    required this.state,
    required Iterable<SixRoomVariant> variants,
  }) : variants = List.unmodifiable(variants);

  final String roomId;
  final String userId;
  final String liveId;
  final String nick;
  final String title;
  final String avatar;
  final String cover;
  final String category;
  final int? popularity;
  final int? followers;
  final SixRoomState state;
  final List<SixRoomVariant> variants;

  SixRoomRoom enrich(SixRoomRoom known) => SixRoomRoom(
    roomId: roomId,
    userId: userId.isEmpty ? known.userId : userId,
    liveId: liveId.isEmpty ? known.liveId : liveId,
    nick: nick == 'Six Rooms' ? known.nick : nick,
    title: title == 'Six Rooms' ? known.title : title,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    cover: cover.isEmpty ? known.cover : cover,
    category: category.isEmpty ? known.category : category,
    popularity: popularity ?? known.popularity,
    followers: followers ?? known.followers,
    state: state == SixRoomState.unknown ? known.state : state,
    variants: variants,
  );
}

final class SixRoomPage {
  SixRoomPage({required Iterable<SixRoomRoom> rooms, required this.hasMore}) : rooms = List.unmodifiable(rooms);

  final List<SixRoomRoom> rooms;
  final bool hasMore;
}

typedef SixRoomRequest = Future<({int status, String body})> Function(
  Uri uri,
  Map<String, String> headers,
  Map<String, String>? form,
  CancelToken cancel,
);

class SixRoomApi {
  SixRoomApi({required SixRoomRequest request, this.deadline = const Duration(seconds: 20), DateTime Function()? clock})
    : _request = request,
      _clock = clock ?? DateTime.now;

  static const String webOrigin = 'https://v.6.cn';
  static const String mobileOrigin = 'https://ios.6.cn';
  static const String mediaOrigin = 'https://wlive.6rooms.com';
  static const int responseLimit = 8 * 1024 * 1024;
  static const Duration directoryCacheLifetime = Duration(seconds: 90);
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  static const String mobileUserAgent = 'ios/7.830 (ios 17.0; ; iPhone 15 (A2846/A3089/A3090/A3092))';
  static const List<SixRoomCategory> categories = [
    SixRoomCategory(id: 'all', name: '全部'),
    SixRoomCategory(id: 'song', name: '歌区', area: '歌区'),
    SixRoomCategory(id: 'dance', name: '舞区', area: '舞区'),
    SixRoomCategory(id: 'talk', name: '脱口秀', area: '脱口秀'),
    SixRoomCategory(id: 'face', name: '星颜', area: '星颜'),
    SixRoomCategory(id: 'party', name: '派对', area: '派对'),
  ];
  static const Map<String, String> webHeaders = {
    'User-Agent': userAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.7',
    'Referer': '$webOrigin/',
  };
  static const Map<String, String> mobileHeaders = {
    'User-Agent': mobileUserAgent,
    'Accept': 'application/json,text/plain,*/*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.7',
    'Referer': '$mobileOrigin/?ver=8.0.3&build=4',
  };

  static Map<String, String> mediaHeaders(String roomId) => {
    'User-Agent': mobileUserAgent,
    'Origin': webOrigin,
    'Referer': SixRoomLink.watchUrl(roomId),
  };

  final SixRoomRequest _request;
  final DateTime Function() _clock;
  final Duration deadline;
  List<SixRoomRoom>? _directoryCache;
  DateTime? _directoryFetchedAt;

  Future<T> _scope<T>(CancelToken? caller, Future<T> Function(CancelToken) work) =>
      withRequestCancellation(caller, (transport) async {
        if (transport.isCancelled) throw const SixRoomException(SixRoomFailure.cancelled);
        try {
          return await Future.any<T>([
            work(transport),
            transport.whenCancel.then<T>((_) => throw const SixRoomException(SixRoomFailure.cancelled)),
          ]).timeout(deadline);
        } on TimeoutException {
          throw const SixRoomException(SixRoomFailure.transport);
        } catch (error) {
          if (caller?.isCancelled == true || transport.isCancelled) {
            throw const SixRoomException(SixRoomFailure.cancelled);
          }
          if (error is SixRoomException) rethrow;
          throw const SixRoomException(SixRoomFailure.transport);
        }
      });

  Future<String> _send(Uri uri, Map<String, String> headers, Map<String, String>? form, CancelToken cancel) async {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw const SixRoomException(SixRoomFailure.identity);
    }
    final response = await _request(uri, headers, form, cancel);
    if (response.status < 200 || response.status >= 300) _throwStatus(response.status);
    if (response.body.length > responseLimit) throw const SixRoomException(SixRoomFailure.schema);
    return response.body;
  }

  Future<SixRoomPage> directory({
    required int page,
    required int pageSize,
    String categoryId = 'all',
    CancelToken? cancel,
  }) => _scope(cancel, (token) async {
    if (page < 1 || page > 10000 || pageSize < 1 || pageSize > 100) {
      throw const SixRoomException(SixRoomFailure.schema);
    }
    final category = categories.where((item) => item.id == categoryId).firstOrNull;
    if (category == null) throw const SixRoomException(SixRoomFailure.identity);
    // The lobby document is large and already contains every category.
    // Refresh the canonical "all" first page; category switches reuse that
    // snapshot briefly instead of downloading the same document again.
    final rooms = await _directory(token, forceRefresh: page == 1 && categoryId == 'all');
    final filtered = category.area == null
        ? rooms
        : rooms.where((room) => room.category == category.area).toList(growable: false);
    final start = (page - 1) * pageSize;
    if (start >= filtered.length) return SixRoomPage(rooms: const [], hasMore: false);
    final end = (start + pageSize).clamp(0, filtered.length);
    return SixRoomPage(rooms: filtered.sublist(start, end), hasMore: end < filtered.length);
  });

  Future<List<SixRoomRoom>> _directory(CancelToken token, {required bool forceRefresh}) async {
    final cached = _directoryCache;
    final fetchedAt = _directoryFetchedAt;
    final cacheFresh =
        cached != null &&
        fetchedAt != null &&
        !_clock().isBefore(fetchedAt) &&
        _clock().difference(fetchedAt) < directoryCacheLifetime;
    if (!forceRefresh && cacheFresh) return cached;
    final body = await _send(Uri.parse('$webOrigin/'), webHeaders, null, token);
    final rooms = parseDirectoryHtml(body);
    _directoryCache = rooms;
    _directoryFetchedAt = _clock();
    return rooms;
  }

  Future<List<SixRoomRoom>> search(String keyword, {CancelToken? cancel}) => _scope(cancel, (token) async {
    final value = keyword.trim();
    if (value.isEmpty || value.length > 80) throw const SixRoomException(SixRoomFailure.schema);
    final uri = Uri.parse('$webOrigin/search.php').replace(queryParameters: {'type': 'use', 'key': value});
    final body = await _send(uri, webHeaders, null, token);
    return parseSearchHtml(body);
  });

  Future<SixRoomRoom> room(String rawRoomId, {String? knownUserId, bool includeMedia = true, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        final roomId = SixRoomLink.parseRoomId(rawRoomId);
        if (roomId == null) throw const SixRoomException(SixRoomFailure.identity);
        var userId = _validUserId(knownUserId) ? knownUserId!.trim() : '';
        if (userId.isEmpty) {
          final html = await _send(Uri.parse(SixRoomLink.watchUrl(roomId)), webHeaders, null, token);
          userId = parseRoomUserIdHtml(html, roomId);
        }
        final body = await _send(
          Uri.parse('$webOrigin/coop/mobile/index.php?padapi=coop-mobile-inroom.php'),
          mobileHeaders,
          {'av': '3.1', 'encpass': '', 'logiuid': '', 'project': 'v6iphone', 'rate': '1', 'rid': '', 'ruid': userId},
          token,
        );
        return parseRoomJson(body, expectedRoomId: roomId, expectedUserId: userId, includeMedia: includeMedia);
      });

  static List<SixRoomRoom> parseDirectoryHtml(String source) {
    final root = _decodeEmbeddedRoot(source);
    Object? rawRooms = root['typeList'];
    if (rawRooms is String) {
      try {
        rawRooms = jsonDecode(rawRooms);
      } on FormatException {
        throw const SixRoomException(SixRoomFailure.schema);
      }
    }
    if (rawRooms is! List) throw const SixRoomException(SixRoomFailure.schema);
    final seen = <String>{};
    final rooms = <SixRoomRoom>[];
    for (final value in rawRooms) {
      final row = _map(value);
      if (row == null) continue;
      final roomId = _string(row['rid']);
      final userId = _string(row['uid']);
      final liveId = _string(row['liveid'] ?? row['lid']);
      if (SixRoomLink.parseRoomId(roomId) != roomId || !_validUserId(userId) || !seen.add(roomId)) continue;
      final nick = _text(row['username'], fallback: 'Six Rooms');
      final title = _firstText([row['livetitle'], row['userMood'], nick], fallback: 'Six Rooms');
      rooms.add(
        SixRoomRoom(
          roomId: roomId,
          userId: userId,
          liveId: liveId,
          nick: nick,
          title: title,
          avatar: _image(row['picuser']),
          cover: _firstImage([row['pospic'], row['pic'], row['pospic_sp']]),
          category: _text(row['anchor_area']),
          popularity: _integer(row['count']),
          followers: null,
          state: SixRoomState.live,
          variants: const [],
        ),
      );
    }
    if (rooms.isEmpty) throw const SixRoomException(SixRoomFailure.schema);
    return List.unmodifiable(rooms);
  }

  static List<SixRoomRoom> parseSearchHtml(String source) {
    final document = html_parser.parse(source);
    final page = document.querySelector('.page-search-user');
    if (page == null) {
      if (document.querySelector('.remind') != null) throw const SixRoomException(SixRoomFailure.access);
      throw const SixRoomException(SixRoomFailure.schema);
    }
    final seen = <String>{};
    final rooms = <SixRoomRoom>[];
    for (final item in page.querySelectorAll('ul.search-user > li[data-uid]')) {
      final userId = (item.attributes['data-uid'] ?? '').trim();
      final href = item.querySelector('a.user-box')?.attributes['href'] ?? '';
      final roomId = SixRoomLink.parseRoomId(Uri.parse(webOrigin).resolve(href).toString());
      if (roomId == null || !_validUserId(userId) || !seen.add(roomId)) continue;
      final image = item.querySelector('.pic img');
      final nick = _text(item.querySelector('.alias')?.text, fallback: 'Six Rooms');
      rooms.add(
        SixRoomRoom(
          roomId: roomId,
          userId: userId,
          liveId: '',
          nick: nick,
          title: nick,
          avatar: _firstImage([image?.attributes['data-src'], image?.attributes['src']]),
          cover: '',
          category: '',
          popularity: null,
          followers: null,
          state: SixRoomState.unknown,
          variants: const [],
        ),
      );
    }
    return List.unmodifiable(rooms);
  }

  static String parseRoomUserIdHtml(String source, String expectedRoomId) {
    final roomId = SixRoomLink.parseRoomId(expectedRoomId);
    if (roomId == null) throw const SixRoomException(SixRoomFailure.identity);
    final document = html_parser.parse(source);
    final canonical = document.querySelector('link[rel="canonical"]')?.attributes['href'] ?? '';
    if (SixRoomLink.parseRoomId(canonical) != roomId) {
      if (document.querySelector('.remind') != null || source.length < 4096) {
        throw const SixRoomException(SixRoomFailure.missing);
      }
      throw const SixRoomException(SixRoomFailure.identity);
    }
    final expression = RegExp(r'''\brid\s*:\s*['"]([1-9]\d{1,12})['"]\s*,\s*roomid\s*:\s*['"]([1-9]\d{1,11})['"]''');
    for (final match in expression.allMatches(source)) {
      if (match.group(2) == roomId) return match.group(1)!;
    }
    throw const SixRoomException(SixRoomFailure.schema);
  }

  static SixRoomRoom parseRoomJson(
    String source, {
    required String expectedRoomId,
    required String expectedUserId,
    bool includeMedia = true,
  }) {
    final roomId = SixRoomLink.parseRoomId(expectedRoomId);
    if (roomId == null || !_validUserId(expectedUserId)) {
      throw const SixRoomException(SixRoomFailure.identity);
    }
    final root = _decode(source);
    if (_string(root['flag']) != '001') throw const SixRoomException(SixRoomFailure.access);
    final content = _map(root['content']);
    final roomInfo = _map(content?['roominfo']);
    final liveInfo = _map(content?['liveinfo']);
    final params = _map(content?['roomParamInfo']);
    if (content == null || roomInfo == null || liveInfo == null || params == null) {
      throw const SixRoomException(SixRoomFailure.schema);
    }
    final actualRoomId = _string(roomInfo['rid']);
    final actualUserId = _string(roomInfo['id'] ?? params['uid']);
    if (actualRoomId != roomId || actualUserId != expectedUserId) {
      throw const SixRoomException(SixRoomFailure.identity);
    }
    final liveId = _string(liveInfo['id']);
    final flvTitle = _string(liveInfo['flvtitle']);
    final privateRoom = _truthy(content['isPriveRoom']);
    final blackScreen = _text(_map(content['blackScreenInfo'])?['msg']);
    final state = privateRoom || blackScreen.isNotEmpty
        ? SixRoomState.restricted
        : liveId.isNotEmpty && flvTitle.isNotEmpty
        ? SixRoomState.live
        : SixRoomState.offline;
    final nick = _text(roomInfo['alias'], fallback: 'Six Rooms');
    final title = _firstText([liveInfo['title'], roomInfo['userMood'], nick], fallback: 'Six Rooms');
    final variants = <SixRoomVariant>[];
    if (includeMedia && state == SixRoomState.live) {
      final media = mediaUri(userId: actualUserId, liveId: liveId, flvTitle: flvTitle);
      if (media != null) {
        final metadata = _streamMetadata(liveInfo, flvTitle);
        variants.add(
          SixRoomVariant(
            id: 'flv:source',
            protocol: 'flv',
            resolution: _text(metadata?['resolution']),
            bitrate: _integer(metadata?['videoBitrate'] ?? metadata?['bitrate']),
            urls: [media],
          ),
        );
      }
    }
    return SixRoomRoom(
      roomId: roomId,
      userId: actualUserId,
      liveId: liveId,
      nick: nick,
      title: title,
      avatar: _firstImage([roomInfo['headPicUrl'], roomInfo['picuser']]),
      cover: _firstImage([liveInfo['spredPic'], liveInfo['pospic'], liveInfo['largepic'], liveInfo['pic']]),
      category: _firstText([roomInfo['anchor_area'], roomInfo['rtypename']]),
      popularity: null,
      followers: _integer(params['fans_num']),
      state: state,
      variants: variants,
    );
  }

  static Uri? mediaUri({required String userId, required String liveId, required String flvTitle}) {
    if (!_validUserId(userId) || !_validUserId(liveId)) return null;
    if (!RegExp('^v${RegExp.escape(userId)}-${RegExp.escape(liveId)}(?:-many)?\$').hasMatch(flvTitle)) return null;
    final uri = Uri.tryParse('$mediaOrigin/httpflv/$flvTitle.flv');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'wlive.6rooms.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.path != '/httpflv/$flvTitle.flv') {
      return null;
    }
    return uri;
  }

  static Map<String, dynamic>? _streamMetadata(Map<String, dynamic> liveInfo, String flvTitle) {
    final content = _map(liveInfo['content']);
    if (content == null) return null;
    for (final value in content.values) {
      final lane = _map(value);
      final streamInfo = _map(lane?['streamInfo']);
      final exact = _map(streamInfo?[flvTitle]);
      if (exact != null) return exact;
    }
    return null;
  }

  static Map<String, dynamic> _decodeEmbeddedRoot(String source) {
    const marker = 'window.__SMARTY_ALL_VARIABLES__ = ';
    final markerAt = source.indexOf(marker);
    if (markerAt < 0) throw const SixRoomException(SixRoomFailure.schema);
    final start = source.indexOf('{', markerAt + marker.length);
    if (start < 0) throw const SixRoomException(SixRoomFailure.schema);
    var depth = 0;
    var quoted = false;
    var escaped = false;
    for (var index = start; index < source.length; index++) {
      final code = source.codeUnitAt(index);
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (code == 0x5c) {
          escaped = true;
        } else if (code == 0x22) {
          quoted = false;
        }
        continue;
      }
      if (code == 0x22) {
        quoted = true;
      } else if (code == 0x7b) {
        depth++;
      } else if (code == 0x7d) {
        depth--;
        if (depth == 0) return _decode(source.substring(start, index + 1));
      }
    }
    throw const SixRoomException(SixRoomFailure.schema);
  }

  static Map<String, dynamic> _decode(String source) {
    try {
      final value = jsonDecode(source);
      final map = _map(value);
      if (map == null) throw const SixRoomException(SixRoomFailure.schema);
      return map;
    } on FormatException {
      throw const SixRoomException(SixRoomFailure.schema);
    }
  }

  static Map<String, dynamic>? _map(Object? value) {
    if (value is! Map) return null;
    return value.map((key, item) => MapEntry(key.toString(), item));
  }

  static String _string(Object? value) => value?.toString().trim() ?? '';

  static String _text(Object? value, {String fallback = ''}) {
    final text = _string(value).replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.isEmpty ? fallback : text;
  }

  static String _firstText(Iterable<Object?> values, {String fallback = ''}) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  static int? _integer(Object? value) {
    if (value is int) return value >= 0 ? value : null;
    if (value is num) return value >= 0 ? value.toInt() : null;
    final parsed = int.tryParse(_string(value).replaceAll(',', ''));
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static bool _truthy(Object? value) => value == true || value == 1 || _string(value) == '1';

  static bool _validUserId(String? value) => value != null && RegExp(r'^[1-9]\d{1,12}$').hasMatch(value.trim());

  static String _image(Object? value) {
    var raw = _string(value);
    if (raw.startsWith('//')) raw = 'https:$raw';
    if (raw.startsWith('http://')) raw = 'https://${raw.substring(7)}';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasPort || uri.fragment.isNotEmpty) {
      return '';
    }
    final host = uri.host.toLowerCase();
    if (host != '6.cn' &&
        !host.endsWith('.6.cn') &&
        host != '6rooms.com' &&
        !host.endsWith('.6rooms.com') &&
        host != 'xiu123.cn' &&
        !host.endsWith('.xiu123.cn')) {
      return '';
    }
    return uri.toString();
  }

  static String _firstImage(Iterable<Object?> values) {
    for (final value in values) {
      final image = _image(value);
      if (image.isNotEmpty) return image;
    }
    return '';
  }

  static Never _throwStatus(int status) {
    if (status >= 200 && status < 300) throw StateError('status accepted before error mapping');
    if (status == 404 || status == 410) throw const SixRoomException(SixRoomFailure.missing);
    if (status == 429) throw const SixRoomException(SixRoomFailure.rateLimited);
    if (status == 401 || status == 403 || (status >= 300 && status < 400)) {
      throw const SixRoomException(SixRoomFailure.access);
    }
    if (status >= 500) throw const SixRoomException(SixRoomFailure.service);
    throw const SixRoomException(SixRoomFailure.transport);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

// sixroom_site.dart

final class SixRoomSite {
  SixRoomSite({required SixRoomApi api}) : _api = api;

  final SixRoomApi _api;
  final Map<String, SixRoomRoom> _known = {};

  String get id => 'sixroom';

  String get name => i18n('site_sixroom');

  String get directoryNoticeKey => 'sixroom_directory_scope';

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    if (page != 1 || pageSize < 1) return const [];
    return [
      LiveCategory(
        id: id,
        name: name,
        children: SixRoomApi.categories
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
    if (category == null) return 'all';
    if (category.platform != id || category.areaType != 'official') {
      throw const SixRoomException(SixRoomFailure.identity);
    }
    final categoryId = category.areaId?.trim() ?? '';
    if (!SixRoomApi.categories.any((item) => item.id == categoryId)) {
      throw const SixRoomException(SixRoomFailure.identity);
    }
    return categoryId;
  }

  void _remember(Iterable<SixRoomRoom> rooms) {
    for (var room in rooms) {
      final known = _known[room.roomId];
      if (known != null) room = room.enrich(known);
      _known[room.roomId] = room;
    }
  }

  static LiveRoom _room(SixRoomRoom room, {required bool includeMedia}) {
    final popularity = room.popularity?.toString();
    final notices = <String>[
      if (room.state == SixRoomState.restricted) i18n('sixroom_restricted_notice'),
      i18n('sixroom_chat_notice'),
    ];
    return LiveRoom(
      platform: 'sixroom',
      roomId: room.roomId,
      userId: room.userId,
      title: room.title,
      nick: room.nick,
      avatar: room.avatar.isEmpty ? room.cover : room.avatar,
      cover: room.cover,
      area: room.category.isEmpty ? i18n('site_sixroom') : room.category,
      link: SixRoomLink.watchUrl(room.roomId),
      liveStatus: switch (room.state) {
        SixRoomState.live => LiveStatus.live,
        SixRoomState.offline => LiveStatus.offline,
        SixRoomState.restricted || SixRoomState.unknown => LiveStatus.unknown,
      },
      watching: popularity ?? '',
      popularity: popularity,
      followers: room.followers?.toString(),
      audienceMetricType: popularity == null ? AudienceMetricType.unknown : AudienceMetricType.popularity,
      notice: notices.join('\n'),
      httpHeaders: SixRoomApi.mediaHeaders(room.roomId),
      data: includeMedia ? room : null,
    );
  }

  Future<LiveDirectoryPage> _directoryPage({
    required int page,
    required int pageSize,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    if (page < 1 || pageSize < 1) return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
    final result = await _api.directory(
      page: page,
      pageSize: pageSize.clamp(1, 100),
      categoryId: _categoryId(category),
      cancel: cancel,
    );
    _remember(result.rooms);
    return LiveDirectoryPage(
      rooms: result.rooms.map((room) => _room(_known[room.roomId]!, includeMedia: false)).toList(growable: false),
      page: page,
      hasMore: result.hasMore,
    );
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) =>
      _directoryPage(page: page, pageSize: 30, category: category, cancel: cancel);

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await _directoryPage(page: page, pageSize: pageSize)).rooms;

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      (await _directoryPage(page: page, pageSize: pageSize, category: category)).rooms;

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
    final roomId = SixRoomLink.parseRoomId(raw);
    if (roomId != null) {
      if (page != 1) return const [];
      try {
        return [await _detail(roomId, id, includeMedia: false, cancel: cancel)];
      } on SixRoomException catch (error) {
        if (error.kind == SixRoomFailure.missing) return const [];
        rethrow;
      }
    }
    if (page != 1) return const [];
    final rooms = await _api.search(raw, cancel: cancel);
    _remember(rooms);
    return rooms.take(pageSize).map((room) => _room(_known[room.roomId]!, includeMedia: false)).toList(growable: false);
  }

  String _roomId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const SixRoomException(SixRoomFailure.identity);
    final value = SixRoomLink.parseRoomId(roomId);
    if (value == null) throw const SixRoomException(SixRoomFailure.identity);
    return value;
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia, CancelToken? cancel}) async {
    final normalized = _roomId(roomId, platform);
    final known = _known[normalized];
    var room = await _api.room(normalized, knownUserId: known?.userId, includeMedia: includeMedia, cancel: cancel);
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
    if (room.effectiveLiveStatus == LiveStatus.unknown) throw const SixRoomException(SixRoomFailure.access);
    return room.isLiveNow;
  }

  SixRoomRoom _snapshot(LiveRoom detail) {
    final roomId = _roomId(detail.roomId ?? '', detail.platform ?? '');
    final room = detail.data;
    if (room is! SixRoomRoom || room.roomId != roomId) throw const SixRoomException(SixRoomFailure.identity);
    if (room.state != SixRoomState.live || room.variants.isEmpty) {
      throw const SixRoomException(SixRoomFailure.mediaUnavailable);
    }
    return room;
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    _roomId(detail.roomId ?? '', detail.platform ?? '');
    if (detail.isExplicitlyOfflineNow) return const [];
    final room = _snapshot(detail);
    return List.unmodifiable(
      room.variants.map((variant) {
        final metadata = <String>[
          if (variant.resolution.isNotEmpty) variant.resolution,
          if (variant.bitrate != null) '${variant.bitrate} kbps',
        ];
        return LivePlayQuality(
          id: variant.id,
          quality: metadata.isEmpty
              ? i18n('sixroom_quality_source')
              : i18n('sixroom_quality_source_detail', args: {'detail': metadata.join(' · ')}),
          sort: variant.bitrate ?? 1,
        );
      }),
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
    throw const SixRoomException(SixRoomFailure.mediaUnavailable);
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
