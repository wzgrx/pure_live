// Writes expected.json for the JD Live samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.28-jdlive.md, "样本与 v3 的冻结输出").
//
// The archive has no JD Live expected.json (its legacy harness only covered
// five platforms, spec/sites/jdlive.md §11, and 3.x no longer builds). The
// code below is 3.x's JdLiveApi, JdLiveLink and JdLiveSite, copied from
// legacy/lib/core/site/jdlive/ (archive/v4) by a script that only makes the
// edits listed here, and `withRequestCancellation` from
// legacy/lib/core/common/request_scope.dart. 3.x already injected its
// transport (`JdLiveRequest`), so only that function is replaced: it answers
// from the samples by host, path and query. The clock values are not
// compared: the `v` and `t` query parameters and the `timestamp` of the list
// request's `body` (3.x read `DateTime.now()`); the requests are written
// without them, and a flow that pages records whether its list requests
// shared one `timestamp` (`timestamps`, one token per distinct value). A
// request without a sample throws a StateError, which 3.x's `_scope` reports
// as a `transport` failure; it is also listed under `unmatched`. Request
// headers other than 3.x's `apiHeaders` are written after the URL.
//
// Edits to 3.x's code: the imports; the network-only `_defaultRequest` and
// `_readBody` are left out, so the transport is required; `extends LiveSite
// implements …`, the `@override` marks and the danmaku getter are left out;
// the site's default api is required. `i18n` returns 3.x's zh.json text of
// the keys used. Dio's CancelToken is a stub; 3.x's LiveRoom, LiveArea,
// LiveCategory, LivePlayQuality, LivePlayUrlResolution and
// LiveDirectoryPage are reduced to the parts these classes use (constructor
// defaults, the mutable fields, the state getters, selectionId, toJson with
// 3.x's HttpHeaderPolicy.normalize).
//
// Samples: S01-list-p1/-p2, S02-play-live/-old and S03-detail-403 are the
// archive's (2026-09-27); S04-list, S04-play-live and S04-playlist were
// recorded for M4.28 at one moment (2026-09-28), so 3.x's room entry (which
// downloads and checks the HLS playlist) runs on real answers. The archived
// live room (S02-play-live) has no recorded playlist; its room entry is
// answered with S04-playlist's body under S02's stream key
// (`withS04Playlist`). Synthetic variants of the recorded answers pin 3.x's
// rules (`variants`).
//
// The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`); every call also records the
// requests it sent.
//
// Run from the repository root: dart run fixtures/jdlive/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/jdlive';

/// The archived live room (S01-list-p1's first card, S02-play-live).
const _archivedLive = '48378944';

/// The archived old id (S02-play-old: status 3 without addresses).
const _archivedOld = '10000';

/// The room of the M4.28 samples (S04-list's first card, S04-play-live).
const _live = '48395626';

/// Keywords run through 3.x's search against S01 (and the play samples for
/// the exact lookups): a title, a shop name in another case, digits in a
/// title, many matches, spaces around, no match, the archived ids and their
/// room links, a URL of another site and a blank.
const _keywords = [
  '海信',
  'obox',
  'OBOX',
  '0821',
  '旗舰店',
  ' 旗舰店 ',
  'zxqvnomatch',
  _archivedLive,
  _archivedOld,
  'https://lives.jd.com/#/$_archivedLive?origin=0',
  'https://lives.jd.com/#/$_archivedLive/live',
  'https://example.com/x',
  '  ',
];

/// Inputs for 3.x's `JdLiveLink.parseLiveId` (no requests).
const _links = [
  _archivedLive,
  ' $_archivedLive ',
  '1234',
  '12345',
  '0123456',
  '123456789012345678',
  '1234567890123456789',
  'https://lives.jd.com/#/$_archivedLive',
  'https://lives.jd.com/#/$_archivedLive?origin=0',
  'https://lives.jd.com/#/$_archivedLive/live?origin=0',
  'https://lives.jd.com/#/$_archivedLive/notice',
  'https://lives.jd.com/#/$_archivedLive/closed',
  'https://lives.jd.com/#/$_archivedLive/replay',
  'https://lives.jd.com/#/$_archivedLive/other',
  'https://lives.jd.com/#/$_archivedLive/live/extra',
  'https://lives.jd.com/#$_archivedLive',
  'http://lives.jd.com/#/$_archivedLive',
  'HTTPS://LIVES.JD.COM/#/$_archivedLive',
  'https://lives.jd.com:443/#/$_archivedLive',
  'http://lives.jd.com:80/#/$_archivedLive',
  'https://lives.jd.com:8443/#/$_archivedLive',
  'https://user@lives.jd.com/#/$_archivedLive',
  'https://lives.jd.com/$_archivedLive',
  'https://lives.jd.com/?origin=0#/$_archivedLive',
  'https://lives.jd.com/#/channel',
  'https://lives.jd.com/',
  'https://lives.jd.com.evil.test/#/$_archivedLive',
  'https://m.jd.com/product/$_archivedLive.html',
  'ftp://lives.jd.com/#/$_archivedLive',
  '看直播 https://lives.jd.com/#/$_archivedLive 快来',
];

void main() async {
  await _list();
  await _page2();
  await _playLive();
  await _playOld();
  await _forbidden();
  await _s04();
  await _playlist();
}

// Harness ---------------------------------------------------------------------

/// A recorded (or synthetic) answer to a request for [url].
final class _Answer {
  _Answer(this.url, this.status, this.body);

  final Uri url;
  final int status;
  final String body;
}

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

String _body(String sample) => File('$_root/$sample/${_meta(sample)['body']}').readAsStringSync();

Uri _url(String sample) => Uri.parse((_meta(sample)['request'] as Map<String, dynamic>)['url'] as String);

/// [sample]'s answer; [body], [status] and [url] replace the recorded ones.
_Answer _sample(String sample, {String? body, int? status, Uri? url}) => _Answer(
  url ?? _url(sample),
  status ?? (_meta(sample)['response'] as Map<String, dynamic>)['status'] as int,
  body ?? _body(sample),
);

List<_Answer> _answers = [];
final List<String> _requests = [];
final List<String> _unmatched = [];
final List<int> _timestamps = [];

void _replay(List<_Answer> answers) {
  _answers = answers;
  _requests.clear();
  _unmatched.clear();
  _timestamps.clear();
}

/// The query as compared and written: without the clock (`v`, `t`, the
/// body's `timestamp`).
Map<String, String> _compared(Uri uri) => {
  for (final MapEntry(:key, :value) in uri.queryParameters.entries)
    if (key != 'v' && key != 't') key: key == 'body' ? _withoutClock(value) : value,
};

String _withoutClock(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) return body;
  return jsonEncode({...decoded}..remove('timestamp'));
}

bool _same(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

String _line(Uri uri, Map<String, String> headers) {
  final query = _compared(uri);
  final pairs = [for (final MapEntry(:key, :value) in query.entries) '$key=$value'];
  final url = '${uri.scheme}://${uri.host}${uri.path}${pairs.isEmpty ? '' : '?${pairs.join('&')}'}';
  final sameHeaders =
      headers.length == JdLiveApi.apiHeaders.length &&
      headers.entries.every((entry) => JdLiveApi.apiHeaders[entry.key] == entry.value);
  return sameHeaders ? 'GET $url' : 'GET $url headers ${jsonEncode(headers)}';
}

/// 3.x's `JdLiveRequest` over the answers.
Future<({int status, String body})> _fixtureRequest(Uri uri, Map<String, String> headers, CancelToken cancel) async {
  final line = _line(uri, headers);
  _requests.add(line);
  final body = uri.queryParameters['body'];
  if (body != null) {
    final timestamp = (jsonDecode(body) as Map)['timestamp'];
    if (timestamp is int) _timestamps.add(timestamp);
  }
  final compared = _compared(uri);
  for (final answer in _answers) {
    if (answer.url.host == uri.host && answer.url.path == uri.path && _same(_compared(answer.url), compared)) {
      return (status: answer.status, body: answer.body);
    }
  }
  _unmatched.add(line);
  throw StateError('No recorded sample for $uri');
}

JdLiveApi _api() => JdLiveApi(request: _fixtureRequest);

JdLiveSite _site() => JdLiveSite(api: _api());

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

/// The list requests' `timestamp`s since [_replay] or the last call, one
/// token per distinct value in order of appearance.
List<String> _timestampTokens() {
  final tokens = <int, String>{};
  final result = [for (final value in _timestamps) tokens.putIfAbsent(value, () => 't${tokens.length}')];
  _timestamps.clear();
  return result;
}

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()..['link'] = room.link;
  json.removeWhere(
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

Object? _page(LiveDirectoryPage page) => {'rooms': _rooms(page.rooms), 'page': page.page, 'hasMore': page.hasMore};

/// Room ids only, for results whose rooms another entry already lists in
/// full.
List<String?> _ids(List<LiveRoom> rooms) => [for (final room in rooms) room.roomId];

Object? _pageIds(LiveDirectoryPage page) => {'roomIds': _ids(page.rooms), 'page': page.page, 'hasMore': page.hasMore};

Object? _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
];

Object? _resolution(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
};

Object? _jdRoom(JdLiveRoom room) => {
  'liveId': room.liveId,
  'authorId': room.authorId,
  'nick': room.nick,
  'title': room.title,
  'avatar': room.avatar,
  'cover': room.cover,
  'totalViews': room.totalViews,
  'state': room.state.name,
  'hls': room.hls?.toString(),
  'flv': room.flv?.toString(),
};

Object? _jdPage(JdLivePage page) => {
  'rooms': [for (final room in page.rooms) _jdRoom(room)],
  'nextCount': page.nextCount,
  'hasMore': page.hasMore,
};

final _featured = LiveArea(
  platform: 'jdlive',
  areaType: 'official',
  areaId: 'featured',
  areaName: '精选直播购物',
  typeName: 'JD Live',
);

LivePlayQuality _quality(String id) => LivePlayQuality(id: id, quality: id);

/// [sample]'s JSON body with `data` fields replaced (null removes one), or
/// the root fields in [root].
String _edited(String sample, {Map<String, Object?> data = const {}, Map<String, Object?> root = const {}}) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  final fields = json['data'] as Map<String, dynamic>;
  for (final MapEntry(:key, :value) in data.entries) {
    if (value == null) {
      fields.remove(key);
    } else {
      fields[key] = value;
    }
  }
  for (final MapEntry(:key, :value) in root.entries) {
    if (value == null) {
      json.remove(key);
    } else {
      json[key] = value;
    }
  }
  return jsonEncode(json);
}

/// [sample]'s list with the room card at [index] (of the `templateType 1`
/// cards) edited by [edit].
String _editedCard(String sample, void Function(Map<String, dynamic> card) edit, {int index = 0}) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  final cards = [
    for (final card in (json['data'] as Map<String, dynamic>)['list'] as List)
      if ((card as Map<String, dynamic>)['templateType'] == 1) card,
  ];
  edit(cards[index]);
  return jsonEncode(json);
}

/// [sample]'s list with its `data` edited by [edit].
String _editedList(String sample, void Function(Map<String, dynamic> data) edit) {
  final json = jsonDecode(_body(sample)) as Map<String, dynamic>;
  edit(json['data'] as Map<String, dynamic>);
  return jsonEncode(json);
}

// Samples ---------------------------------------------------------------------

List<_Answer> _archivedAnswers() => [
  _sample('S01-list-p1'),
  _sample('S01-list-p2'),
  _sample('S02-play-live'),
  _sample('S02-play-old'),
];

/// The featured list: the category, the native directory, the
/// recommendations and the area, 3.x's search over it, the list cards
/// enriching a detail, the link rules and 3.x's list checks.
Future<void> _list() async {
  _replay(_archivedAnswers());
  final value = <String, Object?>{
    'headers': {
      'apiHeaders': JdLiveApi.apiHeaders,
      'mediaHeaders($_archivedLive)': JdLiveApi.mediaHeaders(_archivedLive),
    },
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
    'getCategores(pageSize: 0)': await _traced(() => _site().getCategores(1, 0), (categories) => categories.length),
    'parseDirectoryJson': _sync(() => _jdPage(JdLiveApi.parseDirectoryJson(jsonDecode(_body('S01-list-p1')), page: 1))),
  };
  // One site pages the directory: page 1, 2, then 3 (not recorded).
  var site = _site();
  _timestamps.clear();
  value['getDirectoryPage'] = {
    for (final page in [1, 2, 3]) 'page $page': await _traced(() => site.getDirectoryPage(page: page), _page),
    'timestamps': _timestampTokens(),
    'featured page 1': await _traced(() => _site().getDirectoryPage(page: 1, category: _featured), _pageIds),
    'otherArea': await _traced(
      () => _site().getDirectoryPage(
        category: LiveArea(platform: 'jdlive', areaType: 'official', areaId: 'other'),
      ),
      _page,
    ),
    'otherPlatform': await _traced(
      () => _site().getDirectoryPage(
        category: LiveArea(platform: 'bilibili', areaType: 'official', areaId: 'featured'),
      ),
      _page,
    ),
    'page 0': await _traced(() => _site().getDirectoryPage(page: 0), _page),
    'page 2 first': await _traced(() => _site().getDirectoryPage(page: 2), _page),
  };
  site = _site();
  _timestamps.clear();
  final recommend = <String, Object?>{
    'page 1 size 30': await _traced(() => site.getRecommendRooms(page: 1, pageSize: 30), _ids),
    'page 2 size 30': await _traced(() => site.getRecommendRooms(page: 2, pageSize: 30), _ids),
    'timestamps': _timestampTokens(),
  };
  for (final (page, size) in [(1, 10), (1, 31), (1, 1), (0, 30), (1, 0), (2, 30)]) {
    recommend['fresh page $page size $size'] = await _traced(
      () => _site().getRecommendRooms(page: page, pageSize: size),
      _ids,
    );
  }
  // The directory and the recommendations keep separate sequences.
  site = _site();
  await site.getDirectoryPage(page: 1);
  recommend['page 2 after directory page 1'] = await _traced(() => site.getRecommendRooms(page: 2), _ids);
  value['getRecommendRooms'] = recommend;
  site = _site();
  value['getCategoryRooms'] = {
    'featured page 1': await _traced(() => site.getCategoryRooms(_featured, page: 1), _ids),
    'featured page 2': await _traced(() => site.getCategoryRooms(_featured, page: 2), _ids),
    'featured page 1 size 5': await _traced(() => _site().getCategoryRooms(_featured, page: 1, pageSize: 5), _ids),
    'otherArea': await _traced(
      () => _site().getCategoryRooms(LiveArea(platform: 'jdlive', areaType: 'official', areaId: 'other')),
      _ids,
    ),
  };
  final search = <String, Object?>{};
  for (final keyword in _keywords) {
    search[keyword] = await _traced(
      () => _site().searchRoomsCancellable(keyword, cancel: CancelToken()),
      keyword.contains('旗舰店') ? _ids : _rooms,
    );
  }
  site = _site();
  _timestamps.clear();
  search['旗舰店 page 1 then 2'] = {
    'page 1': await _traced(() => site.searchRoomsCancellable('旗舰店', page: 1, cancel: CancelToken()), _ids),
    'page 2': await _traced(() => site.searchRoomsCancellable('旗舰店', page: 2, cancel: CancelToken()), _ids),
    'timestamps': _timestampTokens(),
  };
  search['旗舰店 page 2 first'] = await _traced(
    () => _site().searchRoomsCancellable('旗舰店', page: 2, cancel: CancelToken()),
    _ids,
  );
  search['旗舰店 size 3'] = await _traced(
    () => _site().searchRoomsCancellable('旗舰店', pageSize: 3, cancel: CancelToken()),
    _ids,
  );
  search['旗舰店 size 100'] = await _traced(
    () => _site().searchRoomsCancellable('旗舰店', pageSize: 100, cancel: CancelToken()),
    _ids,
  );
  search['旗舰店 size 101'] = await _traced(
    () => _site().searchRoomsCancellable('旗舰店', pageSize: 101, cancel: CancelToken()),
    _ids,
  );
  search['$_archivedLive page 2'] = await _traced(
    () => _site().searchRoomsCancellable(_archivedLive, page: 2, cancel: CancelToken()),
    _rooms,
  );
  search['海信 without a token'] = await _traced(() => _site().searchRooms('海信'), _rooms);
  value['searchRoomsCancellable'] = search;
  // The list cards fill what the play answer lacks (3.x's `_known`).
  site = _site();
  final known = <String, Object?>{
    'getRoomDetailForRefresh before the list': await _traced(
      () => site.getRoomDetailForRefresh(roomId: _archivedLive, platform: 'jdlive'),
      _roomProjection,
    ),
    'getDirectoryPage 1': await _traced(() => site.getDirectoryPage(page: 1), (page) => page.rooms.length),
    'getRoomDetailForRefresh after the list': await _traced(
      () => site.getRoomDetailForRefresh(roomId: _archivedLive, platform: 'jdlive'),
      _roomProjection,
    ),
    'searchRooms after the list': await _traced(() => site.searchRooms(_archivedLive), _rooms),
  };
  final search2 = _site();
  await search2.searchRoomsCancellable('海信', cancel: CancelToken());
  known['getRoomDetailForRefresh after a search'] = await _traced(
    () => search2.getRoomDetailForRefresh(roomId: _archivedLive, platform: 'jdlive'),
    _roomProjection,
  );
  value['known'] = known;
  value['JdLiveLink.parseLiveId'] = {for (final link in _links) link: JdLiveLink.parseLiveId(link)};
  value['JdLiveLink.watchUrl'] = {
    for (final id in [_archivedLive, ' $_archivedLive ', 'https://lives.jd.com/#/$_archivedLive/live', 'abc'])
      id: _sync(() => JdLiveLink.watchUrl(id)),
  };
  value['variants'] = _listVariants();
  _write(
    'S01-list-p1',
    'JdLiveSite.getCategores + getDirectoryPage + getRecommendRooms + getCategoryRooms + searchRoomsCancellable '
        '(with S01-list-p2, S02-play-live, S02-play-old) + JdLiveApi.parseDirectoryJson + JdLiveLink; '
        'variants: parseDirectoryJson of edited copies',
    value,
  );
}

/// 3.x's list checks on edited copies of S01-list-p1.
Map<String, Object?> _listVariants() {
  Object? parse(String body) => _sync(() => _jdPage(JdLiveApi.parseDirectoryJson(jsonDecode(body), page: 1)));
  Object? card(void Function(Map<String, dynamic> card) edit, {int index = 0}) {
    final result = parse(_editedCard('S01-list-p1', edit, index: index));
    if (result is Map && result['rooms'] is List) {
      return {...result, 'rooms': (result['rooms'] as List).take(2).toList()};
    }
    return result;
  }

  Object? summary(String body) {
    final result = parse(body);
    if (result is Map && result['rooms'] is List) return {...result, 'rooms': (result['rooms'] as List).length};
    return result;
  }

  Map<String, dynamic> data(Map<String, dynamic> card) => card['data'] as Map<String, dynamic>;
  return {
    'userName null': card((c) => data(c)['userName'] = null),
    'userName number': card((c) => data(c)['userName'] = 7),
    'title blank': card((c) => data(c)['title'] = '  \n '),
    'title spaced': card((c) => data(c)['title'] = ' a\n\tb  c '),
    'userPic http': card((c) => data(c)['userPic'] = 'http://img30.360buyimg.com/a.png'),
    'userPic other host': card((c) => data(c)['userPic'] = 'https://example.com/a.png'),
    'userPic protocol-relative': card((c) => data(c)['userPic'] = '//img30.360buyimg.com/a.png'),
    'userPic number': card((c) => data(c)['userPic'] = 1),
    'indexImage missing': card((c) => data(c).remove('indexImage')),
    'userPic missing': card((c) => data(c).remove('userPic')),
    'pv negative': card((c) => data(c)['pv'] = -1),
    'pv text': card((c) => data(c)['pv'] = '12'),
    'pv missing': card((c) => data(c).remove('pv')),
    'status 0': card((c) => data(c)['status'] = 0),
    'status 2': card((c) => data(c)['status'] = 2),
    'status 3': card((c) => data(c)['status'] = 3),
    'status 10': card((c) => data(c)['status'] = 10),
    'status 99': card((c) => data(c)['status'] = 99),
    'status missing': card((c) => data(c).remove('status')),
    'authorId missing': card((c) => data(c).remove('authorId')),
    'liveId differs from id': card((c) => data(c)['liveId'] = '48000001'),
    'liveId missing': card((c) => data(c).remove('liveId')),
    'id missing': card((c) => data(c).remove('id')),
    'liveId short': card((c) {
      data(c)['liveId'] = '1234';
      data(c)['id'] = 1234;
    }),
    'second card repeats the first': card((c) {
      data(c)['liveId'] = '48378944';
      data(c)['id'] = 48378944;
    }, index: 1),
    'templateType text': card((c) => c['templateType'] = '1'),
    'templateType 2': card((c) => c['templateType'] = 2),
    'data not an object': card((c) => c['data'] = 'x'),
    'list item not an object': parse(_editedList('S01-list-p1', (d) => (d['list'] as List).insert(0, 5))),
    'list not a list': parse(_editedList('S01-list-p1', (d) => d['list'] = {})),
    'list empty': parse(_editedList('S01-list-p1', (d) => d['list'] = [])),
    'currentCount missing': parse(_editedList('S01-list-p1', (d) => d.remove('currentCount'))),
    'currentCount text': summary(_editedList('S01-list-p1', (d) => d['currentCount'] = '37')),
    'code 2': parse(_edited('S01-list-p1', root: {'code': '2'})),
    'code number 0': summary(_edited('S01-list-p1', root: {'code': 0})),
    'subCode 1': parse(_edited('S01-list-p1', root: {'subCode': '1'})),
    'subCode missing': parse(_edited('S01-list-p1', root: {'subCode': null})),
    'data missing': parse(jsonEncode({'code': '0', 'subCode': '0'})),
  };
}

/// Page 2 of the featured list (it follows page 1 in S01-list-p1's flows).
Future<void> _page2() async {
  _write('S01-list-p2', 'JdLiveApi.parseDirectoryJson (page 2)', {
    'parseDirectoryJson': _sync(() => _jdPage(JdLiveApi.parseDirectoryJson(jsonDecode(_body('S01-list-p2')), page: 2))),
  });
}

/// The rooms at every depth, the live status, the qualities, the URLs and
/// the recovery of [id], with every request.
Future<Map<String, Object?>> _roomCalls(String id) async {
  final site = _site();
  final entry = <String, Object?>{
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: id, platform: 'jdlive'), _roomProjection),
    'getRoomDetailForRefresh': await _traced(
      () => site.getRoomDetailForRefresh(roomId: id, platform: 'jdlive'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _traced(
      () => site.getRoomDetailForRecording(roomId: id, platform: 'jdlive'),
      _roomProjection,
    ),
    'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: id, platform: 'jdlive'), (live) => live),
  };
  for (final depth in ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording']) {
    final fresh = _site();
    LiveRoom? detail;
    try {
      detail = await switch (depth) {
        'getRoomDetail' => fresh.getRoomDetail(roomId: id, platform: 'jdlive'),
        'getRoomDetailForRefresh' => fresh.getRoomDetailForRefresh(roomId: id, platform: 'jdlive'),
        _ => fresh.getRoomDetailForRecording(roomId: id, platform: 'jdlive'),
      };
    } on Object {
      detail = null;
    }
    if (detail == null) continue;
    final room = detail;
    entry['$depth → getPlayQualites'] = await _traced(() => fresh.getPlayQualites(detail: room), _qualities);
    for (final quality in ['hls', 'flv', 'auto']) {
      entry['$depth → resolvePlayUrlsRaw($quality)'] = await _traced(
        () => fresh.resolvePlayUrlsRaw(detail: room, quality: _quality(quality)),
        _resolution,
      );
    }
    entry['$depth → resolvePlayUrlsForRecoveryRaw(hls)'] = await _traced(
      () => fresh.resolvePlayUrlsForRecoveryRaw(detail: room, quality: _quality('hls')),
      _resolution,
    );
    entry['$depth → getPlayUrls(flv)'] = await _traced(
      () => fresh.getPlayUrls(detail: room, quality: _quality('flv')),
      (urls) => urls,
    );
  }
  entry['otherPlatform'] = await _traced(
    () => _site().getRoomDetail(roomId: id, platform: 'bilibili'),
    _roomProjection,
  );
  entry['platform in another case'] = await _traced(
    () => _site().getRoomDetailForRefresh(roomId: id, platform: ' JDLive '),
    _roomProjection,
  );
  entry['room link as id'] = await _traced(
    () => _site().getRoomDetailForRefresh(roomId: 'https://lives.jd.com/#/$id/live', platform: 'jdlive'),
    _roomProjection,
  );
  return entry;
}

/// S04-playlist's body under [stem] (another stream's key).
String _playlistFor(String stem) => _body('S04-playlist').replaceAll('F366C61365FB1F9B4BC62D90DBE239B1', stem);

/// The archived live play answer: every depth (room entry with S04's
/// playlist under this stream's key), the list cards filling the names,
/// and 3.x's play checks on edited copies.
Future<void> _playLive() async {
  const stem = '834C6A62B3177AB5FDD83B3EAC6DC6EA_fhd';
  final playlist = _Answer(
    Uri.parse('https://zt-pull-ai.jdcloud.com/live/$stem.m3u8'),
    200,
    _playlistFor('834C6A62B3177AB5FDD83B3EAC6DC6EA'),
  );
  _replay([..._archivedAnswers()]);
  final value = <String, Object?>{
    'parseRoomJson': _sync(
      () => _jdRoom(JdLiveApi.parseRoomJson(jsonDecode(_body('S02-play-live')), expectedLiveId: _archivedLive)),
    ),
    'parseRoomJson(other id)': _sync(
      () => _jdRoom(JdLiveApi.parseRoomJson(jsonDecode(_body('S02-play-live')), expectedLiveId: '48378945')),
    ),
    'recorded': await _roomCalls(_archivedLive),
  };
  _replay([..._archivedAnswers(), playlist]);
  value['withS04Playlist'] = await _roomCalls(_archivedLive);
  final site = _site();
  await site.getDirectoryPage(page: 1);
  value['withS04Playlist after the list'] = {
    'getRoomDetail': await _traced(
      () => site.getRoomDetail(roomId: _archivedLive, platform: 'jdlive'),
      _roomProjection,
    ),
  };
  value['variants'] = await _playVariants();
  _write(
    'S02-play-live',
    'JdLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + getPlayUrls + '
        'JdLiveApi.parseRoomJson (with S01-list-p1; withS04Playlist: room entry answered with S04-playlist '
        "under this stream's key); variants: edited copies at every depth",
    value,
  );
}

/// 3.x's play checks: the room at every depth for edited copies of
/// S02-play-live (room entry with S04's playlist under its key).
Future<Map<String, Object?>> _playVariants() async {
  const key = '834C6A62B3177AB5FDD83B3EAC6DC6EA';
  const flv = 'https://zt-pull-ai.jdcloud.com/live/${key}_fhd.flv';
  final variants = <String, ({Map<String, Object?> data, Map<String, Object?> root})>{
    'secret 1': (data: {'secret': 1}, root: {}),
    'secret 1 offline': (data: {'secret': 1, 'status': 2, 'videoUrl': '', 'h5VideoUrl': ''}, root: {}),
    'status 0': (data: {'status': 0}, root: {}),
    'status 2': (data: {'status': 2}, root: {}),
    'status 3': (data: {'status': 3}, root: {}),
    'status 10': (data: {'status': 10}, root: {}),
    'status 11': (data: {'status': 11}, root: {}),
    'status 99': (data: {'status': 99}, root: {}),
    'status text': (data: {'status': '1'}, root: {}),
    'status missing': (data: {'status': null}, root: {}),
    'secret missing': (data: {'secret': null}, root: {}),
    'liveId text': (data: {'liveId': _archivedLive}, root: {}),
    'liveId other': (data: {'liveId': 48378945}, root: {}),
    'videoUrl missing': (data: {'videoUrl': null}, root: {}),
    'videoUrl empty': (data: {'videoUrl': ''}, root: {}),
    'videoUrl number': (data: {'videoUrl': 7}, root: {}),
    'videoUrl http': (data: {'videoUrl': flv.replaceFirst('https:', 'http:')}, root: {}),
    'videoUrl other key': (data: {'videoUrl': flv.replaceFirst(key, 'OTHER')}, root: {}),
    'videoUrl other host': (data: {'videoUrl': flv.replaceFirst('zt-pull-ai.jdcloud.com', 'example.com')}, root: {}),
    'videoUrl other port': (data: {'videoUrl': flv.replaceFirst('.com/', '.com:8443/')}, root: {}),
    'videoUrl not /live/': (data: {'videoUrl': flv.replaceFirst('/live/', '/vod/')}, root: {}),
    'videoUrl with query': (data: {'videoUrl': '$flv?sign=x'}, root: {}),
    'h5VideoUrl missing': (data: {'h5VideoUrl': null}, root: {}),
    'both missing': (data: {'h5VideoUrl': null, 'videoUrl': null}, root: {}),
    'pcVideoUrl only': (data: {'videoUrl': ''}, root: {}),
    'blurredImg missing': (data: {'blurredImg': null}, root: {}),
    'blurredImg other host': (data: {'blurredImg': 'https://example.com/a.jpg'}, root: {}),
    'blurredImg number': (data: {'blurredImg': 3}, root: {}),
    'code 2': (data: {}, root: {'code': '2'}),
    'subCode 1': (data: {}, root: {'subCode': '1'}),
    'data missing': (data: {}, root: {'data': null}),
  };
  final result = <String, Object?>{};
  for (final MapEntry(key: name, :value) in variants.entries) {
    final body = _edited('S02-play-live', data: value.data, root: value.root);
    _replay([
      _sample('S02-play-live', body: body),
      _Answer(Uri.parse('https://zt-pull-ai.jdcloud.com/live/${key}_fhd.m3u8'), 200, _playlistFor(key)),
    ]);
    final site = _site();
    final entry = <String, Object?>{
      'getRoomDetailForRefresh': await _outcome(
        () => site.getRoomDetailForRefresh(roomId: _archivedLive, platform: 'jdlive'),
        _roomProjection,
      ),
      'getLiveStatus': await _outcome(() => site.getLiveStatus(roomId: _archivedLive, platform: 'jdlive'), (l) => l),
    };
    LiveRoom? detail;
    try {
      detail = await site.getRoomDetail(roomId: _archivedLive, platform: 'jdlive');
      entry['getRoomDetail'] = _roomProjection(detail);
    } on Object catch (error) {
      entry['getRoomDetail'] = _errorProjection(error);
    }
    if (detail != null) {
      final room = detail;
      entry['getRoomDetail → getPlayQualites'] = await _outcome(() => site.getPlayQualites(detail: room), _qualities);
      entry['getRoomDetail → resolvePlayUrlsRaw(hls)'] = await _outcome(
        () => site.resolvePlayUrlsRaw(detail: room, quality: _quality('hls')),
        _resolution,
      );
    }
    result[name] = entry;
  }
  return result;
}

/// The archived old id: status 3 without addresses at every depth.
Future<void> _playOld() async {
  _replay(_archivedAnswers());
  _write(
    'S02-play-old',
    'JdLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + getPlayUrls + JdLiveApi.parseRoomJson',
    {
      'parseRoomJson': _sync(
        () => _jdRoom(JdLiveApi.parseRoomJson(jsonDecode(_body('S02-play-old')), expectedLiveId: _archivedOld)),
      ),
      'recorded': await _roomCalls(_archivedOld),
    },
  );
}

/// The empty 403 of the detail endpoint (3.x never asked it), as the answer
/// to 3.x's play request; the other statuses 3.x mapped.
Future<void> _forbidden() async {
  final url = _url('S02-play-live');
  final value = <String, Object?>{};
  for (final status in [403, 401, 404, 429, 400, 422, 500, 503, 302, 204]) {
    _replay([_sample('S03-detail-403', url: url, status: status, body: '')]);
    final site = _site();
    value['status $status'] = {
      'getRoomDetail': await _traced(
        () => site.getRoomDetail(roomId: _archivedLive, platform: 'jdlive'),
        _roomProjection,
      ),
      'getRoomDetailForRefresh': await _traced(
        () => site.getRoomDetailForRefresh(roomId: _archivedLive, platform: 'jdlive'),
        _roomProjection,
      ),
      'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: _archivedLive, platform: 'jdlive'), (l) => l),
      'searchRooms': await _traced(() => site.searchRooms(_archivedLive), _rooms),
    };
  }
  _replay([_sample('S03-detail-403', url: _url('S01-list-p1'), status: 404, body: '')]);
  value['list status 404'] = await _traced(() => _site().getDirectoryPage(page: 1), _page);
  _replay([_sample('S03-detail-403', url: _url('S01-list-p1'), status: 200, body: 'not json')]);
  value['list not JSON'] = await _traced(() => _site().getDirectoryPage(page: 1), _page);
  _write(
    'S03-detail-403',
    "JdLiveSite's detail, live status and search when the play request is answered with this sample's empty "
        'body and each status; the list request answered with 404 and with a body that is not JSON',
    value,
  );
}

List<_Answer> _s04Answers() => [_sample('S04-list'), _sample('S04-play-live'), _sample('S04-playlist')];

/// The M4.28 samples: the list page, the play answer of its first card and
/// that stream's playlist, recorded together.
Future<void> _s04() async {
  _replay(_s04Answers());
  var site = _site();
  _write('S04-list', 'JdLiveApi.parseDirectoryJson + JdLiveSite.getDirectoryPage + getRecommendRooms', {
    'parseDirectoryJson': _sync(() => _jdPage(JdLiveApi.parseDirectoryJson(jsonDecode(_body('S04-list')), page: 1))),
    'getDirectoryPage': {
      'page 1': await _traced(() => site.getDirectoryPage(page: 1), _page),
      'page 2': await _traced(() => site.getDirectoryPage(page: 2), _page),
    },
    'getRecommendRooms': {
      'page 1': await _traced(() => (site = _site()).getRecommendRooms(page: 1), _ids),
      'page 2': await _traced(() => site.getRecommendRooms(page: 2), _ids),
    },
  });
  _replay(_s04Answers());
  final value = <String, Object?>{
    'headers': {'mediaHeaders($_live)': JdLiveApi.mediaHeaders(_live)},
    'parseRoomJson': _sync(
      () => _jdRoom(JdLiveApi.parseRoomJson(jsonDecode(_body('S04-play-live')), expectedLiveId: _live)),
    ),
    'recorded': await _roomCalls(_live),
  };
  site = _site();
  await site.getDirectoryPage(page: 1);
  value['after the list'] = {
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: _live, platform: 'jdlive'), _roomProjection),
    'getRoomDetailForRefresh': await _traced(
      () => site.getRoomDetailForRefresh(roomId: _live, platform: 'jdlive'),
      _roomProjection,
    ),
    'searchRooms': await _traced(() => site.searchRooms(_live), _rooms),
  };
  _replay([_sample('S04-list'), _sample('S04-play-live'), _sample('S04-playlist', body: '#EXTM3U\n')]);
  value['empty playlist'] = await _traced(
    () => _site().getRoomDetail(roomId: _live, platform: 'jdlive'),
    _roomProjection,
  );
  _replay([_sample('S04-list'), _sample('S04-play-live'), _sample('S04-playlist', status: 404, body: '')]);
  value['playlist 404'] = {
    'getRoomDetail': await _traced(() => _site().getRoomDetail(roomId: _live, platform: 'jdlive'), _roomProjection),
    'getRoomDetailForRefresh': await _traced(
      () => _site().getRoomDetailForRefresh(roomId: _live, platform: 'jdlive'),
      _roomProjection,
    ),
  };
  _write(
    'S04-play-live',
    'JdLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + getPlayUrls + '
        'JdLiveApi.parseRoomJson (with S04-playlist, S04-list)',
    value,
  );
}

/// 3.x's playlist check on the recorded playlist and edited copies.
Future<void> _playlist() async {
  final hls = Uri.parse('https://zt-pull-ai.jdcloud.com/live/F366C61365FB1F9B4BC62D90DBE239B1_fhd.m3u8');
  final recorded = _body('S04-playlist');
  final segment = recorded.trim().split('\n').last;
  Object? check(String source) => _sync(() {
    JdLiveApi.validatePlaylist(source, expected: hls);
    return 'ok';
  });
  _write('S04-playlist', 'JdLiveApi.validatePlaylist', {
    'recorded': check(recorded),
    'CRLF': check(recorded.replaceAll('\n', '\r\n')),
    'leading blank': check('\n  $recorded'),
    'other stem': check(recorded.replaceAll('F366C61365FB1F9B4BC62D90DBE239B1_fhd', 'OTHER_fhd')),
    'absolute same host': check(recorded.replaceFirst(segment, 'https://zt-pull-ai.jdcloud.com/live/$segment')),
    'absolute other host': check(recorded.replaceFirst(segment, 'https://example.com/live/$segment')),
    'absolute http': check(recorded.replaceFirst(segment, 'http://zt-pull-ai.jdcloud.com/live/$segment')),
    'host in another case': check(recorded.replaceFirst(segment, 'https://ZT-PULL-AI.jdcloud.com/live/$segment')),
    'port 443': check(recorded.replaceFirst(segment, 'https://zt-pull-ai.jdcloud.com:443/live/$segment')),
    'other port': check(recorded.replaceFirst(segment, 'https://zt-pull-ai.jdcloud.com:8443/live/$segment')),
    'outside /live/': check(recorded.replaceFirst(segment, '../vod/$segment')),
    'root-relative': check(recorded.replaceFirst(segment, '/live/$segment')),
    'fragment': check(recorded.replaceFirst(segment, '$segment#x')),
    'user info': check(recorded.replaceFirst(segment, 'https://u@zt-pull-ai.jdcloud.com/live/$segment')),
    'URI attribute same stream': check(
      recorded.replaceFirst(
        '#EXT-X-DISCONTINUITY\n',
        '#EXT-X-MAP:URI="F366C61365FB1F9B4BC62D90DBE239B1_fhd-init.mp4"\n',
      ),
    ),
    'URI attribute other stream': check(
      recorded.replaceFirst('#EXT-X-DISCONTINUITY\n', '#EXT-X-KEY:URI="https://example.com/k"\n'),
    ),
    'only tags': check('#EXTM3U\n#EXT-X-VERSION:3\n'),
    'only a URI attribute': check('#EXTM3U\n#EXT-X-MAP:URI="F366C61365FB1F9B4BC62D90DBE239B1_fhd-init.mp4"\n'),
    'not a playlist': check('<html></html>'),
    'empty': check(''),
    '1000 segments': check('#EXTM3U\n${List.filled(1000, segment).join('\n')}\n'),
    '1001 segments': check('#EXTM3U\n${List.filled(1001, segment).join('\n')}\n'),
    'over 1 MiB': check('#EXTM3U\n$segment\n#${'x' * (1024 * 1024)}\n'),
  });
}

// Stubs -----------------------------------------------------------------------

/// Dio's CancelToken, reduced to what 3.x's JD Live classes use.
class CancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancel => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

String i18n(String key) =>
    const {
      'jdlive_category_featured': '精选直播购物',
      'jdlive_chat_notice': '京东远端聊天尚待接入；公开目录的 pv 字段按累计观看展示，不标记为当前并发人数。',
      'jdlive_restricted_notice': '该京东直播仅限京东应用访问，界面保持未知状态，不将其显示成未开播。',
      'jdlive_quality_hls': 'HLS（推荐）',
      'jdlive_quality_flv': 'FLV 原始线路',
    }[key] ??
    (throw StateError('No zh.json text for $key'));

// 3.x's request_scope.dart ----------------------------------------------------

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

// 3.x models (the parts the JD Live classes use) -------------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

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

// 3.x's jd_live_api.dart ------------------------------------------------------

enum JdLiveFailure { transport, access, missing, rateLimited, service, schema, identity, cancelled, mediaUnavailable }

final class JdLiveException implements Exception {
  const JdLiveException(this.kind);

  final JdLiveFailure kind;

  @override
  String toString() => 'JD Live ${kind.name}';
}

enum JdLiveState { live, preview, offline, replay, paused, restricted, unknown }

final class JdLiveRoom {
  const JdLiveRoom({
    required this.liveId,
    required this.authorId,
    required this.nick,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.totalViews,
    required this.state,
    required this.hls,
    required this.flv,
  });

  final String liveId;
  final String authorId;
  final String nick;
  final String title;
  final String avatar;
  final String cover;
  final int? totalViews;
  final JdLiveState state;
  final Uri? hls;
  final Uri? flv;

  JdLiveRoom enrich(JdLiveRoom known) => JdLiveRoom(
    liveId: liveId,
    authorId: authorId.isEmpty ? known.authorId : authorId,
    nick: nick == 'JD Live' ? known.nick : nick,
    title: title == 'JD Live' ? known.title : title,
    avatar: avatar.isEmpty ? known.avatar : avatar,
    cover: cover.isEmpty ? known.cover : cover,
    totalViews: totalViews ?? known.totalViews,
    state: state,
    hls: hls,
    flv: flv,
  );
}

final class JdLivePage {
  JdLivePage({required Iterable<JdLiveRoom> rooms, required this.nextCount, required this.hasMore})
    : rooms = List.unmodifiable(rooms);

  final List<JdLiveRoom> rooms;
  final int nextCount;
  final bool hasMore;
}

typedef JdLiveRequest = Future<({int status, String body})> Function(
  Uri uri,
  Map<String, String> headers,
  CancelToken cancel,
);

class JdLiveApi {
  JdLiveApi({required JdLiveRequest request, this.deadline = const Duration(seconds: 20)}) : _request = request;

  static const String apiOrigin = 'https://api.m.jd.com';
  static const String webOrigin = 'https://lives.jd.com';
  static const int responseLimit = 4 * 1024 * 1024;
  static const String userAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
  static const Map<String, String> apiHeaders = {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Origin': webOrigin,
    'Referer': '$webOrigin/',
  };

  static Map<String, String> mediaHeaders(String liveId) => {
    'User-Agent': userAgent,
    'Origin': webOrigin,
    'Referer': JdLiveLink.watchUrl(liveId),
  };

  final JdLiveRequest _request;
  final Duration deadline;

  Future<T> _scope<T>(CancelToken? caller, Future<T> Function(CancelToken) work) =>
      withRequestCancellation(caller, (transport) async {
        if (transport.isCancelled) throw const JdLiveException(JdLiveFailure.cancelled);
        try {
          return await Future.any<T>([
            work(transport),
            transport.whenCancel.then<T>((_) => throw const JdLiveException(JdLiveFailure.cancelled)),
          ]).timeout(deadline);
        } on TimeoutException {
          throw const JdLiveException(JdLiveFailure.transport);
        } catch (error) {
          if (caller?.isCancelled == true || transport.isCancelled) {
            throw const JdLiveException(JdLiveFailure.cancelled);
          }
          if (error is JdLiveException) rethrow;
          throw const JdLiveException(JdLiveFailure.transport);
        }
      });

  Future<String> _get(Uri uri, Map<String, String> headers, CancelToken cancel) async {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment) {
      throw const JdLiveException(JdLiveFailure.identity);
    }
    final response = await _request(uri, headers, cancel);
    _throwStatus(response.status);
    if (response.body.length > responseLimit) throw const JdLiveException(JdLiveFailure.schema);
    return response.body;
  }

  Future<JdLivePage> directory({
    required int page,
    required int currentCount,
    required int timestamp,
    CancelToken? cancel,
  }) => _scope(cancel, (token) async {
    if (page < 1 || page > 10000 || currentCount < 0 || timestamp < 1) {
      throw const JdLiveException(JdLiveFailure.schema);
    }
    final body = jsonEncode({'tabId': 1, 'currentCount': '$currentCount', 'page': page, 'timestamp': timestamp});
    final uri = Uri.parse('$apiOrigin/api').replace(
      queryParameters: {
        'appid': 'h5-live',
        'functionId': 'liveListWithTabToM',
        'v': '${DateTime.now().millisecondsSinceEpoch}',
        'body': body,
      },
    );
    return parseDirectoryJson(_decode(await _get(uri, apiHeaders, token)), page: page);
  });

  Future<JdLiveRoom> room(String rawLiveId, {bool includeMedia = false, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        final liveId = JdLiveLink.parseLiveId(rawLiveId);
        if (liveId == null) throw const JdLiveException(JdLiveFailure.identity);
        final uri = Uri.parse('$apiOrigin/api').replace(
          queryParameters: {
            'appid': 'h5-live',
            'functionId': 'getImmediatePlayToM',
            't': '${DateTime.now().millisecondsSinceEpoch}',
            'body': jsonEncode({'liveId': liveId}),
          },
        );
        final room = parseRoomJson(_decode(await _get(uri, apiHeaders, token)), expectedLiveId: liveId);
        if (includeMedia && room.state == JdLiveState.live) {
          final hls = room.hls;
          if (hls == null) throw const JdLiveException(JdLiveFailure.mediaUnavailable);
          validatePlaylist(await _get(hls, mediaHeaders(liveId), token), expected: hls);
        }
        return room;
      });

  static JdLivePage parseDirectoryJson(Object? value, {required int page}) {
    if (page < 1) throw const JdLiveException(JdLiveFailure.schema);
    final data = _responseData(value);
    final list = _list(data['list']);
    final seen = <String>{};
    final rooms = <JdLiveRoom>[];
    for (final value in list) {
      final card = _object(value);
      if (_int(card['templateType']) != 1) continue;
      final item = _object(card['data']);
      final liveId = _id(item['liveId'] ?? item['id']);
      if (liveId == null || _id(item['id']) != liveId || !seen.add(liveId)) continue;
      final status = _int(item['status']);
      rooms.add(
        JdLiveRoom(
          liveId: liveId,
          authorId: _id(item['authorId']) ?? '',
          nick: _optionalText(item['userName'], fallback: 'JD Live'),
          title: _optionalText(item['title'], fallback: 'JD Live'),
          avatar: _image(item['userPic']),
          cover: _image(item['indexImage']),
          totalViews: _nonNegativeInt(item['pv']),
          state: _state(status, secret: 0),
          hls: null,
          flv: null,
        ),
      );
    }
    final nextCount = _nonNegativeInt(data['currentCount']);
    if (nextCount == null) throw const JdLiveException(JdLiveFailure.schema);
    return JdLivePage(rooms: rooms, nextCount: nextCount, hasMore: rooms.length >= 30);
  }

  static JdLiveRoom parseRoomJson(Object? value, {required String expectedLiveId}) {
    final liveId = JdLiveLink.parseLiveId(expectedLiveId);
    if (liveId == null) throw const JdLiveException(JdLiveFailure.identity);
    final data = _responseData(value);
    if (_id(data['liveId']) != liveId) throw const JdLiveException(JdLiveFailure.identity);
    final state = _state(_int(data['status']), secret: _int(data['secret']) ?? 0);
    final hls = _mediaUri(data['h5VideoUrl'], extension: '.m3u8');
    final flv = _mediaUri(data['videoUrl'], extension: '.flv');
    if (state == JdLiveState.live && (hls == null || flv == null || _streamKey(hls) != _streamKey(flv))) {
      throw const JdLiveException(JdLiveFailure.schema);
    }
    return JdLiveRoom(
      liveId: liveId,
      authorId: '',
      nick: 'JD Live',
      title: 'JD Live',
      avatar: '',
      cover: _image(data['blurredImg']),
      totalViews: null,
      state: state,
      hls: hls,
      flv: flv,
    );
  }

  static void validatePlaylist(String source, {required Uri expected}) {
    if (source.length > 1024 * 1024 || !source.trimLeft().startsWith('#EXTM3U')) {
      throw const JdLiveException(JdLiveFailure.schema);
    }
    final stem = _streamKey(expected);
    var mediaReferences = 0;
    for (final rawLine in const LineSplitter().convert(source)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        for (final match in RegExp(r'URI="([^"]+)"').allMatches(line)) {
          if (!_validChild(expected, match.group(1)!, stem)) {
            throw const JdLiveException(JdLiveFailure.schema);
          }
          mediaReferences++;
        }
        continue;
      }
      if (!_validChild(expected, line, stem)) throw const JdLiveException(JdLiveFailure.schema);
      mediaReferences++;
      if (mediaReferences > 1000) throw const JdLiveException(JdLiveFailure.schema);
    }
    if (mediaReferences < 1) throw const JdLiveException(JdLiveFailure.schema);
  }

  static Object? _decode(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      throw const JdLiveException(JdLiveFailure.schema);
    }
  }

  static Map<String, dynamic> _responseData(Object? value) {
    final root = _object(value);
    if (_text(root['code']) != '0') throw const JdLiveException(JdLiveFailure.service);
    if (_text(root['subCode']) != '0') throw const JdLiveException(JdLiveFailure.missing);
    return _object(root['data']);
  }

  static JdLiveState _state(int? status, {required int secret}) {
    if (secret == 1) return JdLiveState.restricted;
    return switch (status) {
      1 => JdLiveState.live,
      0 => JdLiveState.preview,
      2 => JdLiveState.offline,
      3 => JdLiveState.replay,
      10 || 11 => JdLiveState.paused,
      _ => JdLiveState.unknown,
    };
  }

  static Uri? _mediaUri(Object? value, {required String extension}) {
    final raw = _optionalText(value);
    if (raw.isEmpty || raw.length > 8192 || RegExp(r'[\s\x00-\x1f]').hasMatch(raw)) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !_hostIs(uri.host, 'jdcloud.com') ||
        (uri.hasPort && uri.port != 443) ||
        !uri.path.startsWith('/live/') ||
        !uri.path.toLowerCase().endsWith(extension)) {
      return null;
    }
    return uri;
  }

  static bool _validChild(Uri expected, String raw, String stem) {
    final child = expected.resolve(raw);
    return child.scheme == 'https' &&
        child.userInfo.isEmpty &&
        !child.hasFragment &&
        child.host.toLowerCase() == expected.host.toLowerCase() &&
        (!child.hasPort || child.port == 443) &&
        child.path.startsWith('/live/') &&
        child.pathSegments.isNotEmpty &&
        child.pathSegments.last.startsWith(stem);
  }

  static String _streamKey(Uri uri) {
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    return name.replaceFirst(RegExp(r'\.(?:m3u8|flv)$', caseSensitive: false), '');
  }

  static String _image(Object? value) {
    final raw = _optionalText(value);
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !_hostIs(uri.host, '360buyimg.com')) {
      return '';
    }
    return uri.toString();
  }

  static bool _hostIs(String host, String root) {
    final value = host.toLowerCase();
    return value == root || value.endsWith('.$root');
  }

  static String? _id(Object? value) {
    final result = switch (value) {
      int number => '$number',
      String text => text.trim(),
      _ => '',
    };
    return RegExp(r'^[1-9]\d{4,17}$').hasMatch(result) ? result : null;
  }

  static int? _int(Object? value) => switch (value) {
    int number => number,
    num number when number.isFinite && number == number.toInt() => number.toInt(),
    String text => int.tryParse(text.trim()),
    _ => null,
  };

  static int? _nonNegativeInt(Object? value) {
    final result = _int(value);
    return result != null && result >= 0 ? result : null;
  }

  static String _text(Object? value) => value is String ? value.trim() : value?.toString().trim() ?? '';

  static String _optionalText(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    if (value is! String || value.length > 65536) throw const JdLiveException(JdLiveFailure.schema);
    final result = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return result.isEmpty ? fallback : result;
  }

  static List<dynamic> _list(Object? value) {
    if (value is! List || value.length > 1000) throw const JdLiveException(JdLiveFailure.schema);
    return value;
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const JdLiveException(JdLiveFailure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static void _throwStatus(int status) {
    final failure = switch (status) {
      200 => null,
      400 || 422 => JdLiveFailure.schema,
      401 || 403 => JdLiveFailure.access,
      404 => JdLiveFailure.missing,
      429 => JdLiveFailure.rateLimited,
      >= 500 => JdLiveFailure.service,
      _ => JdLiveFailure.transport,
    };
    if (failure != null) throw JdLiveException(failure);
  }
}

// 3.x's jd_live_link.dart -----------------------------------------------------

abstract final class JdLiveLink {
  static final RegExp _liveId = RegExp(r'^[1-9]\d{4,17}$');
  static final RegExp _route = RegExp(r'^/?([1-9]\d{4,17})(?:/(?:live|notice|closed|replay))?(?:\?.*)?$');

  static String watchUrl(String raw) => 'https://lives.jd.com/#/${requireLiveId(raw)}';

  static String requireLiveId(String raw) {
    final value = parseLiveId(raw);
    if (value == null) throw const FormatException('Invalid JD Live identity');
    return value;
  }

  static String? parseLiveId(String raw) {
    final value = raw.trim();
    if (_liveId.hasMatch(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'lives.jd.com' ||
        (uri.hasPort && uri.port != 80 && uri.port != 443)) {
      return null;
    }
    final match = _route.firstMatch(uri.fragment);
    return match?.group(1);
  }
}

// 3.x's jd_live_site.dart -----------------------------------------------------

final class JdLiveSite {
  JdLiveSite({JdLiveApi? api}) : _api = api!;

  final JdLiveApi _api;
  final Map<String, JdLiveRoom> _known = {};
  final Map<String, _JdDirectorySequence> _sequences = {};

  String get id => 'jdlive';

  String get name => 'JD Live';

  String get directoryNoticeKey => 'jdlive_directory_scope';

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async => page == 1 && pageSize > 0
      ? [
          LiveCategory(
            id: id,
            name: name,
            children: [
              LiveArea(
                platform: id,
                areaType: 'official',
                areaId: 'featured',
                areaName: i18n('jdlive_category_featured'),
                typeName: name,
              ),
            ],
          ),
        ]
      : [];

  void _category(LiveArea? category) {
    if (category != null &&
        (category.platform != id || category.areaType != 'official' || category.areaId != 'featured')) {
      throw const JdLiveException(JdLiveFailure.identity);
    }
  }

  void _remember(Iterable<JdLiveRoom> rooms) {
    for (final room in rooms) {
      _known[room.liveId] = room;
    }
  }

  static LiveRoom _room(JdLiveRoom room, {required bool includeMedia}) {
    final total = room.totalViews?.toString();
    final status = switch (room.state) {
      JdLiveState.live => LiveStatus.live,
      JdLiveState.preview || JdLiveState.offline || JdLiveState.replay => LiveStatus.offline,
      JdLiveState.restricted || JdLiveState.paused || JdLiveState.unknown => LiveStatus.unknown,
    };
    return LiveRoom(
      platform: 'jdlive',
      roomId: room.liveId,
      userId: room.authorId.isEmpty ? room.liveId : room.authorId,
      title: room.title,
      nick: room.nick,
      avatar: room.avatar.isEmpty ? room.cover : room.avatar,
      cover: room.cover,
      area: 'JD Live',
      link: JdLiveLink.watchUrl(room.liveId),
      liveStatus: status,
      totalViewers: total,
      audienceMetricType: total == null ? AudienceMetricType.unknown : AudienceMetricType.totalViewers,
      notice: room.state == JdLiveState.restricted ? i18n('jdlive_restricted_notice') : i18n('jdlive_chat_notice'),
      httpHeaders: JdLiveApi.mediaHeaders(room.liveId),
      data: includeMedia ? room : null,
    );
  }

  Future<JdLivePage> _directory(String key, int page, CancelToken? cancel) async {
    if (page < 1) return JdLivePage(rooms: const [], nextCount: 0, hasMore: false);
    if (page == 1) {
      _sequences[key] = _JdDirectorySequence(DateTime.now().millisecondsSinceEpoch);
    }
    final sequence = _sequences[key];
    final count = sequence?.counts[page];
    if (sequence == null || count == null) {
      return JdLivePage(rooms: const [], nextCount: 0, hasMore: false);
    }
    final result = await _api.directory(page: page, currentCount: count, timestamp: sequence.timestamp, cancel: cancel);
    _remember(result.rooms);
    if (result.hasMore) {
      sequence.counts[page + 1] = result.nextCount;
    } else {
      sequence.counts.remove(page + 1);
    }
    return result;
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _category(category);
    final result = await _directory('directory', page, cancel);
    return LiveDirectoryPage(
      rooms: result.rooms.map((room) => _room(room, includeMedia: false)),
      page: page,
      hasMore: result.hasMore,
    );
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return [];
    final result = await _directory('recommend', page, null);
    return result.rooms
        .take(pageSize.clamp(1, 30))
        .map((room) => _room(room, includeMedia: false))
        .toList(growable: false);
  }

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _category(category);
    return getRecommendRooms(page: page, pageSize: pageSize);
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
    if (raw.isEmpty || page < 1 || pageSize < 1 || pageSize > 100) return [];
    final liveId = JdLiveLink.parseLiveId(raw);
    if (liveId != null) {
      if (page != 1) return [];
      try {
        return [await _detail(liveId, id, includeMedia: false, cancel: cancel)];
      } on JdLiveException catch (error) {
        if (error.kind == JdLiveFailure.missing) return [];
        rethrow;
      }
    }
    final query = raw.toLowerCase();
    final result = await _directory('search:$query', page, cancel);
    return result.rooms
        .where(
          (room) =>
              room.liveId.contains(query) ||
              room.authorId.contains(query) ||
              room.nick.toLowerCase().contains(query) ||
              room.title.toLowerCase().contains(query),
        )
        .take(pageSize)
        .map((room) => _room(room, includeMedia: false))
        .toList(growable: false);
  }

  String _liveId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const JdLiveException(JdLiveFailure.identity);
    final value = JdLiveLink.parseLiveId(roomId);
    if (value == null) throw const JdLiveException(JdLiveFailure.identity);
    return value;
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia, CancelToken? cancel}) async {
    final liveId = _liveId(roomId, platform);
    var room = await _api.room(liveId, includeMedia: includeMedia, cancel: cancel);
    final known = _known[liveId];
    if (known != null) room = room.enrich(known);
    _known[liveId] = room;
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
      throw const JdLiveException(JdLiveFailure.access);
    }
    return detail.isLiveNow;
  }

  JdLiveRoom _snapshot(LiveRoom detail) {
    final liveId = _liveId(detail.roomId ?? '', detail.platform ?? '');
    final room = detail.data;
    if (room is! JdLiveRoom || room.liveId != liveId || room.state != JdLiveState.live || room.hls == null) {
      throw const JdLiveException(JdLiveFailure.mediaUnavailable);
    }
    return room;
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.isExplicitlyOfflineNow) return const [];
    final room = _snapshot(detail);
    return [
      LivePlayQuality(id: 'hls', quality: i18n('jdlive_quality_hls'), sort: 2),
      if (room.flv != null) LivePlayQuality(id: 'flv', quality: i18n('jdlive_quality_flv'), sort: 1),
    ];
  }

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality, {required bool refresh}) async {
    var room = _snapshot(detail);
    if (refresh) room = _snapshot(await _detail(room.liveId, id, includeMedia: true));
    return switch (quality.selectionId) {
      'hls' => LivePlayUrlResolution(urls: [room.hls!.toString()], appliedQualityData: 'hls'),
      'flv' when room.flv != null => LivePlayUrlResolution(urls: [room.flv!.toString()], appliedQualityData: 'flv'),
      _ => throw const JdLiveException(JdLiveFailure.mediaUnavailable),
    };
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

final class _JdDirectorySequence {
  _JdDirectorySequence(this.timestamp);

  final int timestamp;
  final Map<int, int> counts = {1: 0};
}
