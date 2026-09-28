// Writes expected.json for the PandaTV samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.25-pandalive.md, "v3 的冻结输出").
//
// The archive has no PandaTV expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below is 3.x's
// PandaLiveApi, PandaLiveLink and PandaLiveSite, copied from
// legacy/lib/core/site/pandalive/ (archive/v4). 3.x already injected its
// transport (`PandaLiveRequest`), so only that function is replaced: it
// answers from the samples by method, host, path, the query other than the
// scrubbed IVS `token` and the form fields other than `info` (the samples
// were recorded with `info=media`, 3.x sent `media fanGrade`, whose answer
// only adds a `fanGrade` list 3.x never read), with the empty body 3.x read
// for any status other than 200 (`_defaultRequest` drained it). A request
// without a sample is a StateError; 3.x's `_scope` would turn it into
// `transport`, so it is also kept aside and rethrown after the call: a
// missing sample fails the run.
//
// `_defaultRequest` and `readBody` (the network path) are left out; Dio's
// CancelToken is reduced to the members 3.x used and 3.x's
// `withRequestCancellation` (core/common/request_scope.dart) is copied
// unchanged. `PandaLiveSite` keeps its method bodies without `extends`,
// `implements`, `@override` and `getDanmaku` (`EmptyDanmaku`); its
// constructor needs the API injected. `i18n` returns 3.x's zh.json text.
// 3.x's LiveRoom, LiveArea, LiveCategory, LivePlayQuality,
// LivePlayUrlResolution and LiveDirectoryPage are reduced to the parts these
// classes use. The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`); every entry also records the
// requests it made (the IVS master without its `token`).
//
// Two samples were recorded without the `member/bj` answer 3.x asks first:
// the ended broadcast (`S05-play-castend`, broadcaster `flffl369`) and the
// adult one (`S05-play-needlogin`, `youngddo819`). The harness answers that
// request with `S04-member-live` with the broadcaster's id and number put in
// (and `isAdult` set for the adult one), as the site test does.
//
// Run from the repository root: dart run fixtures/pandalive/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint, unused_field, unused_element
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/pandalive';

void main() async {
  await _directory();
  await _directoryLast();
  await _searchLive();
  await _searchBroadcasters();
  await _live();
  await _offline();
  await _notFound();
  await _refused(
    'S05-play-castend',
    userId: 'flffl369',
    index: 28103135,
    adult: false,
  );
  await _refused(
    'S05-play-needlogin',
    userId: 'youngddo819',
    index: 1000001,
    adult: true,
  );
  await _master();
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final Map<String, String> _synthetic = {};
final List<Map<String, Object?>> _requests = [];
String? _missingSample;

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync())
        as Map<String, dynamic>;

String _body(String sample) {
  final meta = _meta(sample);
  return File('$_root/$sample/${meta['body']}').readAsStringSync();
}

void _load(List<String> samples) {
  _samples = [for (final sample in samples) _meta(sample)];
  _synthetic.clear();
  _requests.clear();
}

const _unmatchedQuery = {'token'};
const _unmatchedForm = {'info'};

Map<String, String> _without(Map<String, String> fields, Set<String> left) => {
  for (final entry in fields.entries)
    if (!left.contains(entry.key)) entry.key: entry.value,
};

bool _same(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);

/// The request as recorded in expected.json: the IVS token left out.
Map<String, Object?> _describe(
  String method,
  Uri uri,
  Map<String, String>? form,
  String referer,
) => {
  'method': method,
  'url': uri
      .replace(
        queryParameters: uri.queryParameters.isEmpty
            ? null
            : _without(uri.queryParameters, _unmatchedQuery),
      )
      .toString()
      .replaceFirst(RegExp(r'\?$'), ''),
  if (form != null) 'form': form,
  'referer': referer,
};

/// 3.x's `_defaultRequest` over the samples: no redirect following, and the
/// body is read only for a 200.
Future<({int status, String body})> _replay(
  String method,
  Uri uri,
  Map<String, String>? form,
  String referer,
  CancelToken cancel,
) async {
  _requests.add(_describe(method, uri, form, referer));
  final synthetic = _synthetic['$method ${uri.path} ${form?['userId']}'];
  if (synthetic != null) return (status: 200, body: synthetic);
  final meta = _samples.where((meta) {
    final request = meta['request'] as Map<String, dynamic>;
    if (request['method'] != method) return false;
    final recorded = Uri.parse(request['url'] as String);
    if (recorded.host != uri.host || recorded.path != uri.path) return false;
    if (!_same(
      _without(recorded.queryParameters, _unmatchedQuery),
      _without(uri.queryParameters, _unmatchedQuery),
    )) {
      return false;
    }
    final body = request['body'];
    final recordedForm = body is String && body.isNotEmpty
        ? Uri.splitQueryString(body)
        : const <String, String>{};
    return _same(
      _without(recordedForm, _unmatchedForm),
      _without(form ?? const {}, _unmatchedForm),
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

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [
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

// Samples ---------------------------------------------------------------------

/// The fixed catalog (no request) and the first page of the public directory
/// by every entry 3.x had, with the calls 3.x refused before a request.
Future<void> _directory() async {
  _load(['S01-index-hot']);
  final site = PandaLiveSite(api: PandaLiveApi(request: _replay));
  final area = (await site.getCategores(1, 30)).single.children.single;
  final first = await site.getDirectoryPage(page: 1);
  _write(
    'S01-index-hot',
    'PandaLiveSite.getCategores + getDirectoryPage(1) + getRecommendRooms(1) + getCategoryRooms(1) + '
        'getPlayQualites(card)',
    {
      'getCategores(1)': await _outcome(
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
      'getCategores(2)': await _outcome(
        () => site.getCategores(2, 30),
        (categories) => categories.length,
      ),
      'directoryNoticeKey': site.directoryNoticeKey,
      'name': site.name,
      'getDirectoryPage(1)': await _outcome(
        () => site.getDirectoryPage(page: 1),
        _pageProjection,
      ),
      'getRecommendRooms(1)': await _outcome(
        () => site.getRecommendRooms(page: 1),
        _rooms,
      ),
      'getCategoryRooms(1)': await _outcome(
        () => site.getCategoryRooms(area, page: 1),
        _rooms,
      ),
      'getDirectoryPage(0)': await _outcome(
        () => site.getDirectoryPage(page: 0),
        _pageProjection,
      ),
      'getDirectoryPage(1, other area)': await _outcome(
        () => site.getDirectoryPage(
          page: 1,
          category: LiveArea(
            platform: 'pandalive',
            areaType: 'directory',
            areaId: 'newbj',
          ),
        ),
        _pageProjection,
      ),
      'getPlayQualites(card)': await _outcome(
        () => site.getPlayQualites(detail: first.rooms.first),
        (qualities) => [
          for (final quality in qualities) _qualityProjection(quality),
        ],
      ),
    },
  );
}

/// The last page (offset 120 of 128).
Future<void> _directoryLast() async {
  _load(['S01-index-hot-last']);
  final site = PandaLiveSite(api: PandaLiveApi(request: _replay));
  _write('S01-index-hot-last', 'PandaLiveSite.getDirectoryPage(5)', {
    'getDirectoryPage(5)': await _outcome(
      () => site.getDirectoryPage(page: 5),
      _pageProjection,
    ),
  });
}

/// The LIVE search alone (20 a page, as recorded), and the site's search of
/// page 1 over both samples: 3.x split a page into ceil(n/2) live and
/// floor(n/2) broadcaster rows and checked that the answer's `page.limit`
/// is the size it asked, so the recorded 20 + 20 is `pageSize` 40.
Future<void> _searchLive() async {
  _load(['S03-search-bj', 'S03-search-live']);
  final api = PandaLiveApi(request: _replay);
  final site = PandaLiveSite(api: api);
  _write(
    'S03-search-live',
    'PandaLiveApi.searchLive(20) as PandaLiveSite._directoryCard + PandaLiveSite.searchRooms(page 1, pageSize 40)',
    {
      'searchLive': await _outcome(
        () => api.searchLive('데이지', size: 20),
        (page) => {
          'page': page.page,
          'hasMore': page.hasMore,
          'rooms': _rooms([
            for (final card in page.rooms) PandaLiveSite._directoryCard(card),
          ]),
        },
      ),
      'searchRooms': await _outcome(
        () => site.searchRooms('데이지', page: 1, pageSize: 40),
        _rooms,
      ),
    },
  );
}

/// The BJ search alone (20 a page, as recorded).
Future<void> _searchBroadcasters() async {
  _load(['S03-search-bj']);
  final api = PandaLiveApi(request: _replay);
  final site = PandaLiveSite(api: api);
  _write(
    'S03-search-bj',
    'PandaLiveApi.searchBroadcasters(20) as PandaLiveSite._room',
    {
      'searchBroadcasters': await _outcome(
        () => api.searchBroadcasters('데이지', size: 20),
        (page) => {
          'page': page.page,
          'hasMore': page.hasMore,
          'rooms': _rooms([
            for (final profile in page.rooms)
              site._room(profile, includeMedia: false),
          ]),
        },
      ),
    },
  );
}

/// Every entry 3.x had for one room: room entry, follow refresh, recording
/// detail, state, qualities with their URLs, resolution, recovery, and the
/// exact-id and link searches.
Future<Map<String, Object?>> _roomEntries(
  PandaLiveSite site,
  String id, {
  bool streams = true,
}) async {
  final value = <String, Object?>{
    'getRoomDetail': await _outcome(
      () => site.getRoomDetail(roomId: id, platform: 'pandalive'),
      _roomProjection,
    ),
    'getRoomDetailForRefresh': await _outcome(
      () => site.getRoomDetailForRefresh(roomId: id, platform: 'pandalive'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _outcome(
      () => site.getRoomDetailForRecording(roomId: id, platform: 'pandalive'),
      _roomProjection,
    ),
    'getLiveStatus': await _outcome(
      () => site.getLiveStatus(roomId: id, platform: 'pandalive'),
      (live) => live,
    ),
  };
  if (!streams) return value;
  late final LiveRoom detail;
  try {
    detail = await site.getRoomDetail(roomId: id, platform: 'pandalive');
  } on StateError {
    rethrow;
  } on Object {
    return value;
  }
  value['getPlayQualites'] = await _outcome(
    () => site.getPlayQualites(detail: detail),
    (qualities) => [
      for (final quality in qualities) _qualityProjection(quality),
    ],
  );
  try {
    final qualities = await site.getPlayQualites(detail: detail);
    value['getPlayUrls'] = {
      for (final quality in qualities)
        '${quality.id}': await site.getPlayUrls(
          detail: detail,
          quality: quality,
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
          () => site.resolvePlayUrlsForRecoveryRaw(
            detail: detail,
            quality: quality,
          ),
          _resolutionProjection,
        ),
    };
  } on StateError {
    rethrow;
  } on Object {
    // Recorded above as getPlayQualites.
  }
  return value;
}

Future<Object?> _searches(PandaLiveSite site, List<String> keywords) async => {
  for (final keyword in keywords)
    keyword: await _outcome(() => site.searchRooms(keyword), _rooms),
};

/// 3.x's link rule over the forms a user may paste.
const _linkVectors = [
  'https://www.pandalive.co.kr/live/play/daisy00',
  'http://pandalive.co.kr/live/play/daisy00',
  'https://m.pandalive.co.kr/live/play/daisy00',
  'https://www.pandalive.co.kr/LIVE/Play/Daisy00',
  'https://www.pandalive.co.kr/channel/daisy00',
  'https://www.pandalive.co.kr/channel/daisy00/home',
  'https://www.pandalive.co.kr//channel//daisy00//',
  'https://www.pandalive.co.kr/channel/1506087545%40ka',
  'https://www.pandalive.co.kr/live/play/daisy00?ref=share',
  'https://www.pandalive.co.kr:443/live/play/daisy00',
  'https://www.pandalive.co.kr/play/daisy00',
  'https://m.pandalive.co.kr/play/daisy00',
  'https://www.pandalive.co.kr/channel/daisy00/notice',
  'https://www.pandalive.co.kr/live',
  'https://www.pandalive.co.kr/search/daisy00',
  'https://www.pandalive.co.kr/live/play/daisy00#chat',
  'https://www.pandalive.co.kr:444/live/play/daisy00',
  'https://user@www.pandalive.co.kr/live/play/daisy00',
  'https://www.pandalive.co.kr.evil.test/live/play/daisy00',
  'https://pandalive.co.kr.evil.test/channel/daisy00',
  'ftp://www.pandalive.co.kr/live/play/daisy00',
  'https://www.pandalive.co.kr/live/play/name@ka/evil',
  'https://www.pandalive.co.kr/live/play/%E4%B8%AD',
  ' https://www.pandalive.co.kr/live/play/daisy00',
];

Future<void> _live() async {
  _load(['S04-member-live', 'S05-play-live', 'S06-master']);
  final site = PandaLiveSite(api: PandaLiveApi(request: _replay));
  final value = await _roomEntries(site, 'daisy00');
  value['searchRooms'] = await _searches(site, [
    'daisy00',
    'https://www.pandalive.co.kr/live/play/daisy00',
    'https://www.pandalive.co.kr/channel/daisy00/home',
    'https://www.pandalive.co.kr/play/daisy00',
  ]);
  value['PandaLiveLink.parse'] = {
    for (final url in _linkVectors) url: PandaLiveLink.parse(url),
  };
  value['PandaLiveLink.parseOrId'] = {
    for (final text in ['daisy00', ' Daisy00 ', '1506087545@ka', '데이지', 'a b'])
      text: PandaLiveLink.parseOrId(text),
  };
  value['PandaLiveLink.url'] = PandaLiveLink.url('daisy00');
  value['PandaLiveApi.mediaHeaders'] = PandaLiveApi.mediaHeaders('daisy00');
  _write(
    'S04-member-live',
    'PandaLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + getPlayUrls + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + searchRooms '
        '(with S05-play-live, S06-master) + PandaLiveLink',
    value,
  );
}

Future<void> _offline() async {
  _load(['S04-member-offline']);
  final site = PandaLiveSite(api: PandaLiveApi(request: _replay));
  final value = await _roomEntries(site, 'flffl369');
  value['searchRooms'] = await _searches(site, [
    'flffl369',
    'https://www.pandalive.co.kr/channel/flffl369',
  ]);
  _write(
    'S04-member-offline',
    'PandaLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + searchRooms',
    value,
  );
}

Future<void> _notFound() async {
  _load(['S04-member-notfound']);
  final site = PandaLiveSite(api: PandaLiveApi(request: _replay));
  final value = await _roomEntries(site, 'zxqvnouserfix', streams: false);
  value['searchRooms'] = await _searches(site, [
    'zxqvnouserfix',
    'https://www.pandalive.co.kr/channel/zxqvnouserfix',
  ]);
  _write(
    'S04-member-notfound',
    'PandaLiveSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'searchRooms',
    value,
  );
}

/// `S04-member-live` as the answer for broadcaster [userId] number [index]:
/// the samples of a refused `live/play` were recorded without it.
String syntheticMember(String userId, int index, {required bool adult}) {
  final member = jsonDecode(_body('S04-member-live')) as Map<String, dynamic>;
  final media = member['media'] as Map<String, dynamic>;
  final info = member['bjInfo'] as Map<String, dynamic>;
  media['userId'] = userId;
  media['userIdx'] = index;
  media['isAdult'] = adult;
  info['id'] = userId;
  info['idx'] = index;
  return jsonEncode(member);
}

/// A `live/play` refusal (HTTP 400): room entry and recording over a member
/// answer that says live, and the play request alone.
Future<void> _refused(
  String sample, {
  required String userId,
  required int index,
  required bool adult,
}) async {
  _load([sample]);
  _synthetic['POST /v1/member/bj $userId'] = syntheticMember(
    userId,
    index,
    adult: adult,
  );
  final api = PandaLiveApi(request: _replay);
  final site = PandaLiveSite(api: api);
  _write(
    sample,
    'PandaLiveSite.getRoomDetail + getRoomDetailForRecording (member/bj: S04-member-live with this id) + '
        'PandaLiveApi._post(live/play)',
    {
      'getRoomDetail': await _outcome(
        () => site.getRoomDetail(roomId: userId, platform: 'pandalive'),
        _roomProjection,
      ),
      'getRoomDetailForRecording': await _outcome(
        () => site.getRoomDetailForRecording(
          roomId: userId,
          platform: 'pandalive',
        ),
        _roomProjection,
      ),
      'live/play': await _outcome(
        () => api._scope(
          null,
          (token) => api._post(
            '/v1/live/play',
            {
              'action': 'watch',
              'userId': userId,
              'password': '',
              'shareLinkType': '',
            },
            PandaLiveLink.url(userId),
            token,
          ),
        ),
        (answer) => answer,
      ),
    },
  );
}

/// The IVS master alone: 3.x's `parseManifest` and the qualities its site
/// made of the streams.
Future<void> _master() async {
  final url = Uri.parse(
    (_meta('S06-master')['request'] as Map<String, dynamic>)['url'] as String,
  );
  final body = _body('S06-master');
  Object? streams;
  Object? qualities;
  try {
    final parsed = PandaLiveApi.parseManifest(url, body);
    streams = [
      for (final stream in parsed)
        {
          'id': stream.id,
          'label': stream.label,
          'height': stream.height,
          'frameRate': stream.frameRate,
          'bandwidth': stream.bandwidth,
          'uri': stream.uri.toString(),
        },
    ];
    qualities = [
      for (final stream in parsed)
        _qualityProjection(
          LivePlayQuality(
            id: stream.id,
            quality: '${stream.label} · HLS',
            sort: stream.height * 10000000 + stream.bandwidth,
          ),
        ),
    ];
  } on Object catch (error) {
    streams = _errorProjection(error);
  }
  _write(
    'S06-master',
    'PandaLiveApi.parseManifest + PandaLiveSite.getPlayQualites naming',
    {'parseManifest': streams, 'qualities': qualities},
  );
}

// 3.x's i18n (assets/translations/zh.json) ----------------------------------------

const Map<String, String> _zh = {
  'site_pandalive': 'PandaTV',
  'pandalive_directory_scope':
      '官网公开直播目录支持原生分页；搜索同时读取当前直播标题/主播与含未开播主播的 BJ 列表，分别按官网原生 offset 翻页。精确频道 ID 和官方直播间/频道链接继续支持。',
  'pandalive_public_directory': '公开直播',
  'pandalive_chat_notice':
      'PandaTV 远端聊天尚待接入；user 字段按平台当前在线人数展示，playCnt 不作为并发人数。',
  'pandalive_adult_notice': '该直播间需要平台成年验证。',
  'pandalive_password_notice': '该直播间需要平台房间密码。',
  'pandalive_restricted_notice': '该直播间存在平台访问条件。',
};

String i18n(String key) =>
    _zh[key] ?? (throw StateError('No zh.json text for $key'));

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

// 3.x models (the parts the PandaTV adapter uses) ----------------------------

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

// 3.x's pandalive_api.dart (imports, `_defaultRequest` and `readBody` left
// out; the transport must be injected) ---------------------------------------
enum PandaLiveFailure {
  transport,
  access,
  missing,
  rateLimited,
  service,
  api,
  schema,
  identity,
  restricted,
  cancelled,
  unknownState,
  mediaUnavailable,
}

class PandaLiveException implements Exception {
  const PandaLiveException(this.kind);
  final PandaLiveFailure kind;

  @override
  String toString() => 'PandaTV ${kind.name}';
}

enum PandaLiveState { live, offline, unknown }

enum PandaLiveAccess { public, password, adult, restricted }

final class PandaLiveCard {
  const PandaLiveCard({
    required this.userId,
    required this.userIndex,
    required this.nickname,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.category,
    required this.onlineViewers,
    required this.followers,
    required this.isAdult,
    required this.isPassword,
  });

  final String userId;
  final int userIndex;
  final String nickname;
  final String title;
  final String avatar;
  final String cover;
  final String category;
  final int? onlineViewers;
  final int? followers;
  final bool isAdult;
  final bool isPassword;
}

final class PandaLiveDirectoryPage {
  PandaLiveDirectoryPage({required Iterable<PandaLiveCard> rooms, required this.page, required this.hasMore})
    : rooms = List.unmodifiable(rooms);

  final List<PandaLiveCard> rooms;
  final int page;
  final bool hasMore;
}

final class PandaLiveSearchPage {
  PandaLiveSearchPage({required Iterable<PandaLiveRoom> rooms, required this.page, required this.hasMore})
    : rooms = List.unmodifiable(rooms);

  final List<PandaLiveRoom> rooms;
  final int page;
  final bool hasMore;
}

final class PandaLiveStream {
  const PandaLiveStream({
    required this.id,
    required this.label,
    required this.height,
    required this.frameRate,
    required this.bandwidth,
    required this.uri,
  });

  final String id;
  final String label;
  final int height;
  final double frameRate;
  final int bandwidth;
  final Uri uri;
}

final class PandaLiveRoom {
  PandaLiveRoom({
    required this.userId,
    required this.userIndex,
    required this.nickname,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.introduction,
    required this.category,
    required this.followers,
    required this.onlineViewers,
    required this.state,
    required this.access,
    required Iterable<PandaLiveStream> streams,
  }) : streams = List.unmodifiable(streams);

  final String userId;
  final int userIndex;
  final String nickname;
  final String title;
  final String avatar;
  final String cover;
  final String introduction;
  final String category;
  final int? followers;
  final int? onlineViewers;
  final PandaLiveState state;
  final PandaLiveAccess access;
  final List<PandaLiveStream> streams;
}

typedef PandaLiveRequest = Future<({int status, String body})> Function(
  String method,
  Uri uri,
  Map<String, String>? form,
  String referer,
  CancelToken cancel,
);

/// Public PandaTV Web contract. Media tokens are scoped to the official
/// Origin, so every metadata, manifest, playback and recording path shares
/// the same request fields.
class PandaLiveApi {
  PandaLiveApi({PandaLiveRequest? request, this.deadline = const Duration(seconds: 20)})
    : _request = request!;

  static const origin = 'https://www.pandalive.co.kr';
  static const apiOrigin = 'https://api.pandalive.co.kr';
  static const responseLimit = 4 * 1024 * 1024;
  static const manifestLimit = 1024 * 1024;
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  static Map<String, String> requestHeaders(String referer) => {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
    'Origin': origin,
    'Referer': referer,
  };

  static Map<String, String> mediaHeaders(String userId) => {
    'User-Agent': userAgent,
    'Origin': origin,
    'Referer': PandaLiveLink.url(userId),
  };

  final PandaLiveRequest _request;
  final Duration deadline;


  Future<T> _scope<T>(CancelToken? caller, Future<T> Function(CancelToken) work) =>
      withRequestCancellation(caller, (transport) async {
        if (transport.isCancelled) throw const PandaLiveException(PandaLiveFailure.cancelled);
        try {
          return await Future.any<T>([
            work(transport),
            transport.whenCancel.then<T>((_) => throw const PandaLiveException(PandaLiveFailure.cancelled)),
          ]).timeout(deadline);
        } on TimeoutException {
          throw const PandaLiveException(PandaLiveFailure.transport);
        } catch (error) {
          if (caller?.isCancelled == true) throw const PandaLiveException(PandaLiveFailure.cancelled);
          if (error is PandaLiveException) rethrow;
          throw const PandaLiveException(PandaLiveFailure.transport);
        }
      });

  Future<String> _read(
    String method,
    Uri uri,
    Map<String, String>? form,
    String referer,
    CancelToken cancel, {
    bool manifest = false,
  }) async {
    if (cancel.isCancelled) throw const PandaLiveException(PandaLiveFailure.cancelled);
    final response = await _request(method, uri, form, referer, cancel);
    if (cancel.isCancelled) throw const PandaLiveException(PandaLiveFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      400 => PandaLiveFailure.schema,
      401 || 403 => PandaLiveFailure.access,
      404 => PandaLiveFailure.missing,
      429 => PandaLiveFailure.rateLimited,
      >= 500 => PandaLiveFailure.service,
      _ => PandaLiveFailure.transport,
    };
    if (failure != null) throw PandaLiveException(failure);
    final limit = manifest ? manifestLimit : responseLimit;
    if (response.body.length > limit || utf8.encode(response.body).length > limit) {
      throw const PandaLiveException(PandaLiveFailure.schema);
    }
    return response.body;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, String> form, String referer, CancelToken cancel) async {
    final body = await _read('POST', Uri.parse('$apiOrigin$path'), form, referer, cancel);
    try {
      return _object(jsonDecode(body));
    } on FormatException {
      throw const PandaLiveException(PandaLiveFailure.schema);
    }
  }

  Future<PandaLiveDirectoryPage> directory({int page = 1, int size = 30, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        _validateRequestPage(page, size);
        final offset = (page - 1) * size;
        final root = await _post(
          '/v1/live/index',
          {'offset': '$offset', 'limit': '$size', 'orderBy': 'hot'},
          '$origin/live',
          token,
        );
        _requireSuccess(root);
        final result = _pagedRows(root, page: page, size: size);
        final rooms = result.rows.map((value) => parseCard(_object(value))).toList(growable: false);
        return PandaLiveDirectoryPage(rooms: rooms, page: page, hasMore: result.hasMore);
      });

  /// Official LIVE search: title and broadcaster matches among current rooms.
  Future<PandaLiveDirectoryPage> searchLive(String keyword, {int page = 1, int size = 10, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        _validateRequestPage(page, size);
        final query = _searchKeyword(keyword);
        final root = await _post(
          '/v1/live/index',
          {'offset': '${(page - 1) * size}', 'limit': '$size', 'orderBy': 'user', 'searchVal': query},
          '$origin/search/live?text=${Uri.encodeQueryComponent(query)}',
          token,
        );
        _requireSuccess(root);
        final result = _pagedRows(root, page: page, size: size);
        final rooms = result.rows.map((value) => parseCard(_object(value))).toList(growable: false);
        return PandaLiveDirectoryPage(rooms: rooms, page: page, hasMore: result.hasMore);
      });

  /// Official BJ search: profiles can be offline and may contain a current
  /// `media` summary. No watch token or media playlist is requested here.
  Future<PandaLiveSearchPage> searchBroadcasters(String keyword, {int page = 1, int size = 10, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        _validateRequestPage(page, size);
        final query = _searchKeyword(keyword);
        final root = await _post(
          '/v1/live/bj_list',
          {'offset': '${(page - 1) * size}', 'limit': '$size', 'searchVal': query},
          '$origin/search/bj?text=${Uri.encodeQueryComponent(query)}',
          token,
        );
        _requireSuccess(root);
        final result = _pagedRows(root, page: page, size: size);
        final rooms = <PandaLiveRoom>[];
        for (final raw in result.rows) {
          try {
            final profile = _object(raw);
            if (_bool(profile['blockService']) == true) continue;
            rooms.add(parseSearchProfile(profile));
          } on PandaLiveException {
            // Keep valid search profiles when an unrelated row is malformed.
          }
        }
        return PandaLiveSearchPage(rooms: rooms, page: page, hasMore: result.hasMore);
      });

  static void _validateRequestPage(int page, int size) {
    if (page < 1 || page > 1000 || size < 1 || size > 50) throw const PandaLiveException(PandaLiveFailure.schema);
  }

  static String _searchKeyword(String keyword) {
    final query = keyword.trim();
    if (query.length < 2 || query.length > 100 || RegExp(r'[\x00-\x1f]').hasMatch(query)) {
      throw const PandaLiveException(PandaLiveFailure.schema);
    }
    return query;
  }

  static ({List<Object?> rows, bool hasMore}) _pagedRows(
    Map<String, dynamic> root, {
    required int page,
    required int size,
  }) {
    final offset = (page - 1) * size;
    final paging = _object(root['page']);
    if (_nonNegativeInt(paging['offset']) != offset ||
        _positiveInt(paging['limit']) != size ||
        _positiveInt(paging['page']) != page) {
      throw const PandaLiveException(PandaLiveFailure.identity);
    }
    final total = _nonNegativeInt(paging['total']);
    final rows = _list(root['list'], max: 64);
    return (rows: rows, hasMore: offset + rows.length < total);
  }

  Future<PandaLiveRoom> room(String rawUserId, {bool resolveMedia = true, CancelToken? cancel}) =>
      _scope(cancel, (token) async {
        final userId = PandaLiveLink.normalizeUserId(rawUserId);
        if (userId == null) throw const PandaLiveException(PandaLiveFailure.identity);
        final referer = PandaLiveLink.url(userId);
        final member = await _post('/v1/member/bj', {'userId': userId, 'info': 'media fanGrade'}, referer, token);
        if (member['result'] != true) {
          final message = _optionalText(member['message']);
          if (message.contains('유저 정보가 없습니다')) throw const PandaLiveException(PandaLiveFailure.missing);
          throw const PandaLiveException(PandaLiveFailure.api);
        }
        final profile = _object(member['bjInfo']);
        final profileId = PandaLiveLink.normalizeUserId(profile['id']);
        if (profileId == null || profileId.toLowerCase() != userId.toLowerCase()) {
          throw const PandaLiveException(PandaLiveFailure.identity);
        }
        final profileIndex = _positiveInt(profile['idx']);
        final mediaValue = member['media'];
        if (mediaValue == null) {
          return _profileRoom(userId, profileIndex, profile);
        }
        final memberMedia = _object(mediaValue);
        _validateMediaIdentity(memberMedia, userId, profileIndex);
        if (!resolveMedia) {
          return _restrictedRoom(userId, profileIndex, profile, memberMedia, PandaLiveAccess.public);
        }
        final play = await _post(
          '/v1/live/play',
          {'action': 'watch', 'userId': userId, 'password': '', 'shareLinkType': ''},
          referer,
          token,
        );
        if (play['result'] != true) {
          final errorData = play['errorData'];
          final code = errorData is Map ? _optionalText(_object(errorData)['code']) : '';
          if (code == 'castEnd') return _profileRoom(userId, profileIndex, profile);
          final access = switch (code) {
            'needAdult' => PandaLiveAccess.adult,
            'needPassword' || 'password' => PandaLiveAccess.password,
            _ => PandaLiveAccess.restricted,
          };
          return _restrictedRoom(userId, profileIndex, profile, memberMedia, access);
        }
        final playMedia = _object(play['media']);
        _validateMediaIdentity(playMedia, userId, profileIndex);
        if (_bool(playMedia['isLive']) != true) return _profileRoom(userId, profileIndex, profile);
        final playlist = _object(play['PlayList']);
        final master = _firstMaster(playlist);
        final manifest = await _read('GET', master, null, referer, token, manifest: true);
        final streams = parseManifest(master, manifest);
        if (streams.isEmpty) throw const PandaLiveException(PandaLiveFailure.mediaUnavailable);
        return _liveRoom(userId, profileIndex, profile, playMedia, streams);
      });

  static PandaLiveCard parseCard(Map<String, dynamic> data) {
    final userId = _userId(data['userId']);
    final live = _bool(data['isLive']);
    if (live != true) throw const PandaLiveException(PandaLiveFailure.schema);
    final userIndex = _positiveInt(data['userIdx']);
    return PandaLiveCard(
      userId: userId,
      userIndex: userIndex,
      nickname: _text(data['userNick']),
      title: _text(data['title']),
      avatar: _image(data['userImg']),
      cover: _image(data['thumbUrl'] ?? data['ivsThumbnail']),
      category: _optionalText(data['category']),
      onlineViewers: _optionalNonNegativeInt(data['user']),
      followers: _optionalNonNegativeInt(data['fanCnt']),
      isAdult: _bool(data['isAdult']) ?? false,
      isPassword: _bool(data['isPw']) ?? false,
    );
  }

  static PandaLiveRoom parseSearchProfile(Map<String, dynamic> profile) {
    final userId = _userId(profile['userId']);
    final userIndex = _positiveInt(profile['userIdx']);
    final nickname = _text(profile['userNick']);
    final avatar = _image(profile['thumbUrl']);
    final rawMedia = profile['media'];
    if (rawMedia == null) {
      return PandaLiveRoom(
        userId: userId,
        userIndex: userIndex,
        nickname: nickname,
        title: nickname,
        avatar: avatar,
        cover: '',
        introduction: '',
        category: '',
        followers: null,
        onlineViewers: null,
        state: PandaLiveState.offline,
        access: PandaLiveAccess.public,
        streams: const [],
      );
    }
    final media = _object(rawMedia);
    _validateMediaIdentity(media, userId, userIndex);
    final live = _bool(media['isLive']);
    return PandaLiveRoom(
      userId: userId,
      userIndex: userIndex,
      nickname: nickname,
      title: _firstText([media['title'], nickname]),
      avatar: avatar,
      cover: _image(media['thumbUrl'] ?? media['ivsThumbnail']),
      introduction: '',
      category: _optionalText(media['category']),
      followers: _optionalNonNegativeInt(media['fanCnt']),
      onlineViewers: live == true ? _optionalNonNegativeInt(media['user']) : null,
      state: switch (live) {
        true => PandaLiveState.live,
        false => PandaLiveState.offline,
        null => PandaLiveState.unknown,
      },
      access: _bool(media['isAdult']) == true
          ? PandaLiveAccess.adult
          : _bool(media['isPw']) == true
          ? PandaLiveAccess.password
          : PandaLiveAccess.public,
      streams: const [],
    );
  }

  static List<PandaLiveStream> parseManifest(Uri master, String source) {
    _mediaUri(master.toString());
    if (source.length > manifestLimit || !source.trimLeft().startsWith('#EXTM3U')) {
      throw const PandaLiveException(PandaLiveFailure.schema);
    }
    final lines = const LineSplitter().convert(source);
    final streams = <PandaLiveStream>[];
    final ids = <String>{};
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trim();
      if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
      final attributes = _attributes(line.substring('#EXT-X-STREAM-INF:'.length));
      var next = index + 1;
      while (next < lines.length && lines[next].trim().isEmpty) {
        next++;
      }
      if (next >= lines.length || lines[next].trim().startsWith('#')) {
        throw const PandaLiveException(PandaLiveFailure.schema);
      }
      final resolution = attributes['RESOLUTION'];
      final match = resolution == null ? null : RegExp(r'^[1-9][0-9]{1,4}x([1-9][0-9]{1,4})$').firstMatch(resolution);
      if (match == null) throw const PandaLiveException(PandaLiveFailure.schema);
      final height = int.parse(match.group(1)!);
      final frameRate = double.tryParse(attributes['FRAME-RATE'] ?? '') ?? 0;
      final bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0;
      if (frameRate < 0 || frameRate > 240 || bandwidth < 0) {
        throw const PandaLiveException(PandaLiveFailure.schema);
      }
      final uri = _mediaUri(master.resolve(lines[next].trim()).toString());
      final fps = frameRate >= 50
          ? '60'
          : frameRate >= 25
          ? '30'
          : '';
      final baseId = '${height}p$fps';
      final id = ids.add(baseId) ? baseId : '${baseId}_${streams.length + 1}';
      streams.add(
        PandaLiveStream(id: id, label: baseId, height: height, frameRate: frameRate, bandwidth: bandwidth, uri: uri),
      );
      index = next;
    }
    streams.sort((left, right) {
      final resolution = right.height.compareTo(left.height);
      if (resolution != 0) return resolution;
      final fps = right.frameRate.compareTo(left.frameRate);
      return fps != 0 ? fps : right.bandwidth.compareTo(left.bandwidth);
    });
    return List.unmodifiable(streams);
  }

  static PandaLiveRoom _profileRoom(String userId, int userIndex, Map<String, dynamic> profile) => PandaLiveRoom(
    userId: userId,
    userIndex: userIndex,
    nickname: _text(profile['nick']),
    title: _firstText([profile['channelTitle'], profile['nick']]),
    avatar: _image(profile['thumbUrl']),
    cover: _image(profile['channelBannerUrl']),
    introduction: _optionalText(profile['channelDesc']),
    category: '',
    followers: _optionalNonNegativeInt(profile['fanCnt']),
    onlineViewers: null,
    state: PandaLiveState.offline,
    access: PandaLiveAccess.public,
    streams: const [],
  );

  static PandaLiveRoom _restrictedRoom(
    String userId,
    int userIndex,
    Map<String, dynamic> profile,
    Map<String, dynamic> media,
    PandaLiveAccess access,
  ) => PandaLiveRoom(
    userId: userId,
    userIndex: userIndex,
    nickname: _text(media['userNick'] ?? profile['nick']),
    title: _firstText([media['title'], profile['channelTitle'], profile['nick']]),
    avatar: _image(media['userImg'] ?? profile['thumbUrl']),
    cover: _image(media['thumbUrl'] ?? profile['channelBannerUrl']),
    introduction: _optionalText(profile['channelDesc']),
    category: _optionalText(media['category']),
    followers: _optionalNonNegativeInt(media['fanCnt'] ?? profile['fanCnt']),
    onlineViewers: _optionalNonNegativeInt(media['user']),
    state: PandaLiveState.live,
    access: access,
    streams: const [],
  );

  static PandaLiveRoom _liveRoom(
    String userId,
    int userIndex,
    Map<String, dynamic> profile,
    Map<String, dynamic> media,
    List<PandaLiveStream> streams,
  ) => PandaLiveRoom(
    userId: userId,
    userIndex: userIndex,
    nickname: _text(media['userNick'] ?? profile['nick']),
    title: _firstText([media['title'], profile['channelTitle'], profile['nick']]),
    avatar: _image(media['userImg'] ?? profile['thumbUrl']),
    cover: _image(media['thumbUrl'] ?? media['ivsThumbnail'] ?? profile['channelBannerUrl']),
    introduction: _optionalText(profile['channelDesc']),
    category: _optionalText(media['category']),
    followers: _optionalNonNegativeInt(media['fanCnt'] ?? profile['fanCnt']),
    onlineViewers: _optionalNonNegativeInt(media['user']),
    state: PandaLiveState.live,
    access: PandaLiveAccess.public,
    streams: streams,
  );

  static void _validateMediaIdentity(Map<String, dynamic> media, String userId, int userIndex) {
    final responseId = _userId(media['userId']);
    if (responseId.toLowerCase() != userId.toLowerCase() || _positiveInt(media['userIdx']) != userIndex) {
      throw const PandaLiveException(PandaLiveFailure.identity);
    }
  }

  static Uri _firstMaster(Map<String, dynamic> playlist) {
    for (final key in const ['hls3', 'hls2', 'hls']) {
      final value = playlist[key];
      if (value == null) continue;
      for (final item in _list(value, max: 16)) {
        final url = _object(item)['url'];
        if (url is String && url.isNotEmpty) return _mediaUri(url);
      }
    }
    throw const PandaLiveException(PandaLiveFailure.mediaUnavailable);
  }

  static Uri _mediaUri(String raw) {
    if (raw.isEmpty || raw.length > 65536 || RegExp(r'[\s\x00-\x1f]').hasMatch(raw)) {
      throw const PandaLiveException(PandaLiveFailure.schema);
    }
    final uri = Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !host.endsWith('.live-video.net') ||
        !uri.path.toLowerCase().endsWith('.m3u8')) {
      throw const PandaLiveException(PandaLiveFailure.schema);
    }
    return uri;
  }

  static Map<String, String> _attributes(String raw) {
    final result = <String, String>{};
    for (final match in RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)').allMatches(raw)) {
      var value = match.group(2)!;
      if (value.startsWith('"') && value.endsWith('"')) value = value.substring(1, value.length - 1);
      result[match.group(1)!] = value;
    }
    return result;
  }

  static void _requireSuccess(Map<String, dynamic> root) {
    if (root['result'] is! bool) throw const PandaLiveException(PandaLiveFailure.schema);
    if (root['result'] != true) throw const PandaLiveException(PandaLiveFailure.api);
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const PandaLiveException(PandaLiveFailure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<Object?> _list(Object? value, {required int max}) {
    if (value is! List || value.length > max) throw const PandaLiveException(PandaLiveFailure.schema);
    return value;
  }

  static String _userId(Object? value) {
    final userId = PandaLiveLink.normalizeUserId(value);
    if (userId == null) throw const PandaLiveException(PandaLiveFailure.identity);
    return userId;
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 8192) {
      throw const PandaLiveException(PandaLiveFailure.schema);
    }
    return value.trim();
  }

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = _optionalText(value);
      if (text.isNotEmpty) return text;
    }
    throw const PandaLiveException(PandaLiveFailure.schema);
  }

  static String _optionalText(Object? value) {
    if (value == null) return '';
    if (value is! String || value.length > 8192) throw const PandaLiveException(PandaLiveFailure.schema);
    return value.trim();
  }

  static String _image(Object? value) {
    final raw = _optionalText(value);
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || !host.endsWith('.pandalive.co.kr')) {
      throw const PandaLiveException(PandaLiveFailure.schema);
    }
    return uri.toString();
  }

  static bool? _bool(Object? value) => switch (value) {
    bool boolean => boolean,
    'Y' || 'y' || 1 => true,
    'N' || 'n' || 0 => false,
    null => null,
    _ => throw const PandaLiveException(PandaLiveFailure.schema),
  };

  static int _positiveInt(Object? value) {
    final number = switch (value) {
      int integer => integer,
      String text when RegExp(r'^[1-9][0-9]{0,15}$').hasMatch(text) => int.parse(text),
      _ => 0,
    };
    if (number <= 0) throw const PandaLiveException(PandaLiveFailure.schema);
    return number;
  }

  static int _nonNegativeInt(Object? value) {
    final number = switch (value) {
      int integer => integer,
      String text when RegExp(r'^[0-9]{1,16}$').hasMatch(text) => int.parse(text),
      _ => -1,
    };
    if (number < 0) throw const PandaLiveException(PandaLiveFailure.schema);
    return number;
  }

  static int? _optionalNonNegativeInt(Object? value) => value == null ? null : _nonNegativeInt(value);
}

// 3.x's pandalive_link.dart, unchanged -------------------------------------------

final class PandaLiveLink {
  const PandaLiveLink._();

  static const _hosts = {'pandalive.co.kr', 'www.pandalive.co.kr', 'm.pandalive.co.kr'};

  static String? parse(String raw) {
    if (raw.length > 8192 || RegExp(r'[\x00-\x20\x7f]').hasMatch(raw)) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) ||
        !_hosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    final segments = uri.pathSegments.where((value) => value.isNotEmpty).toList(growable: false);
    if (segments.length == 3 && segments[0].toLowerCase() == 'live' && segments[1].toLowerCase() == 'play') {
      return normalizeUserId(segments[2]);
    }
    if (segments.length == 2 && segments[0].toLowerCase() == 'channel') {
      return normalizeUserId(segments[1]);
    }
    if (segments.length == 3 && segments[0].toLowerCase() == 'channel' && segments[2].toLowerCase() == 'home') {
      return normalizeUserId(segments[1]);
    }
    return null;
  }

  static String? parseOrId(String raw) => parse(raw.trim()) ?? normalizeUserId(raw.trim());

  static String? normalizeUserId(Object? value) {
    if (value is! String) return null;
    final userId = value.trim();
    // The official BJ index also contains social-login IDs such as
    // 1506087545@ka, which the public member endpoint resolves directly.
    return RegExp(r'^[A-Za-z0-9_]{1,64}(?:@[A-Za-z0-9_]{2,16})?$').hasMatch(userId) ? userId : null;
  }

  static String url(String rawUserId) {
    final userId = normalizeUserId(rawUserId);
    if (userId == null) throw const FormatException('Invalid PandaTV user ID');
    return Uri.https('www.pandalive.co.kr', '/live/play/$userId').toString();
  }
}

// 3.x's pandalive_site.dart (the LiveSite interfaces and the danmaku left out;
// the API must be injected) ----------------------------------------------------

class PandaLiveSite {
  PandaLiveSite({PandaLiveApi? api}) : _api = api!;

  final PandaLiveApi _api;

  String get id => 'pandalive';

  String get name => 'PandaTV';

  String get directoryNoticeKey => 'pandalive_directory_scope';


  Future<List<LiveCategory>> getCategores(int page, int pageSize) async => page == 1
      ? [
          LiveCategory(
            id: id,
            name: name,
            children: [
              LiveArea(
                platform: id,
                areaType: 'directory',
                areaId: 'public',
                areaName: i18n('pandalive_public_directory'),
                typeName: name,
              ),
            ],
          ),
        ]
      : [];

  void _category(LiveArea? category) {
    if (category != null &&
        (category.platform != id || category.areaType != 'directory' || category.areaId != 'public')) {
      throw const PandaLiveException(PandaLiveFailure.identity);
    }
  }

  static LiveRoom _directoryCard(PandaLiveCard room) => LiveRoom(
    platform: 'pandalive',
    roomId: room.userId,
    userId: room.userId,
    title: room.title,
    nick: room.nickname,
    avatar: room.avatar,
    cover: room.cover,
    area: room.category,
    link: PandaLiveLink.url(room.userId),
    liveStatus: LiveStatus.live,
    onlineViewers: room.onlineViewers?.toString(),
    totalViewers: null,
    followers: room.followers?.toString(),
    audienceMetricType: AudienceMetricType.onlineViewers,
    notice: room.isAdult
        ? i18n('pandalive_adult_notice')
        : room.isPassword
        ? i18n('pandalive_password_notice')
        : i18n('pandalive_chat_notice'),
    httpHeaders: PandaLiveApi.mediaHeaders(room.userId),
  );

  LiveRoom _room(PandaLiveRoom room, {required bool includeMedia}) => LiveRoom(
    platform: id,
    roomId: room.userId,
    userId: '${room.userIndex}',
    title: room.title,
    nick: room.nickname,
    avatar: room.avatar,
    cover: room.cover,
    area: room.category,
    link: PandaLiveLink.url(room.userId),
    liveStatus: switch (room.state) {
      PandaLiveState.live => LiveStatus.live,
      PandaLiveState.offline => LiveStatus.offline,
      PandaLiveState.unknown => LiveStatus.unknown,
    },
    onlineViewers: room.onlineViewers?.toString(),
    totalViewers: null,
    followers: room.followers?.toString(),
    introduction: room.introduction,
    audienceMetricType: AudienceMetricType.onlineViewers,
    notice: switch (room.access) {
      PandaLiveAccess.public => i18n('pandalive_chat_notice'),
      PandaLiveAccess.adult => i18n('pandalive_adult_notice'),
      PandaLiveAccess.password => i18n('pandalive_password_notice'),
      PandaLiveAccess.restricted => i18n('pandalive_restricted_notice'),
    },
    httpHeaders: PandaLiveApi.mediaHeaders(room.userId),
    data: includeMedia ? room : null,
  );

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _category(category);
    final result = await _api.directory(page: page, cancel: cancel);
    final seen = <String>{};
    return LiveDirectoryPage(
      page: page,
      hasMore: result.hasMore,
      rooms: result.rooms.where((room) => seen.add(room.userId.toLowerCase())).map(_directoryCard),
    );
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await getDirectoryPage(page: page)).rooms;

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      (await getDirectoryPage(page: page, category: category)).rooms;

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page < 1 || pageSize < 1) return [];
    final query = keyword.trim();
    final linkId = PandaLiveLink.parse(query);
    if (linkId != null) {
      if (page > 1) return [];
      try {
        return [_room(await _api.room(linkId, resolveMedia: false, cancel: cancel), includeMedia: false)];
      } on PandaLiveException catch (error) {
        if (error.kind == PandaLiveFailure.missing) return [];
        rethrow;
      }
    }
    if (Uri.tryParse(query)?.hasScheme == true || query.length < 2 || query.length > 100) return [];
    final exactId = PandaLiveLink.normalizeUserId(query);
    if (page == 1 && exactId != null) {
      try {
        return [_room(await _api.room(exactId, resolveMedia: false, cancel: cancel), includeMedia: false)];
      } on PandaLiveException catch (error) {
        if (error.kind != PandaLiveFailure.missing) rethrow;
      }
    }

    // The official site has separate LIVE (title/broadcaster) and BJ (live
    // plus offline profile) searches. Split the requested page between them,
    // preserving each source's native offset/limit instead of pretending that
    // either endpoint has a combined server cursor.
    final liveSize = pageSize > 1 ? (pageSize + 1) ~/ 2 : 0;
    final bjSize = pageSize - liveSize;
    PandaLiveDirectoryPage? live;
    PandaLiveSearchPage? broadcasters;
    Object? liveError;
    Object? bjError;
    // The public gateway may stall one of two simultaneous same-host POSTs.
    // Query BJ profiles first so offline broadcasters remain discoverable.
    try {
      broadcasters = await _api.searchBroadcasters(query, page: page, size: bjSize.clamp(1, 50), cancel: cancel);
    } catch (error) {
      bjError = error;
    }
    if (cancel?.isCancelled == true) throw const PandaLiveException(PandaLiveFailure.cancelled);
    if (liveSize > 0) {
      try {
        live = await _api.searchLive(query, page: page, size: liveSize.clamp(1, 50), cancel: cancel);
      } catch (error) {
        liveError = error;
      }
    }
    if (cancel?.isCancelled == true) throw const PandaLiveException(PandaLiveFailure.cancelled);
    if (live == null && broadcasters == null) throw (liveError ?? bjError)!;
    final seen = <String>{};
    final rooms = <LiveRoom>[
      for (final card in live?.rooms ?? const <PandaLiveCard>[])
        if (seen.add(card.userId.toLowerCase())) _directoryCard(card),
      for (final profile in broadcasters?.rooms ?? const <PandaLiveRoom>[])
        if (seen.add(profile.userId.toLowerCase())) _room(profile, includeMedia: false),
    ];
    if (rooms.isEmpty && (liveError != null || bjError != null)) throw (liveError ?? bjError)!;
    return List.unmodifiable(rooms);
  }

  String _userId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const PandaLiveException(PandaLiveFailure.identity);
    final userId = PandaLiveLink.normalizeUserId(roomId);
    if (userId == null) throw const PandaLiveException(PandaLiveFailure.identity);
    return userId;
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia}) async {
    final data = await _api.room(_userId(roomId, platform), resolveMedia: includeMedia);
    return _room(data, includeMedia: includeMedia);
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
      throw const PandaLiveException(PandaLiveFailure.unknownState);
    }
    return room.isLiveNow;
  }

  PandaLiveRoom _snapshot(LiveRoom detail) {
    final userId = _userId(detail.roomId ?? '', detail.platform ?? '');
    final data = detail.data;
    if (data is! PandaLiveRoom || data.userId.toLowerCase() != userId.toLowerCase()) {
      throw const PandaLiveException(PandaLiveFailure.identity);
    }
    if (data.state != PandaLiveState.live || data.access != PandaLiveAccess.public || data.streams.isEmpty) {
      throw const PandaLiveException(PandaLiveFailure.mediaUnavailable);
    }
    return data;
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.isExplicitlyOfflineNow) return [];
    final room = _snapshot(detail);
    return List.unmodifiable(
      room.streams.map(
        (stream) => LivePlayQuality(
          id: stream.id,
          quality: '${stream.label} · HLS',
          sort: stream.height * 10000000 + stream.bandwidth,
        ),
      ),
    );
  }

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality, {required bool refresh}) async {
    var room = _snapshot(detail);
    if (refresh) room = _snapshot(await getRoomDetail(roomId: room.userId, platform: id));
    final selectionId = quality.selectionId.toString();
    for (final stream in room.streams) {
      if (stream.id == selectionId) {
        return LivePlayUrlResolution(urls: [stream.uri.toString()], appliedQualityData: selectionId);
      }
    }
    throw const PandaLiveException(PandaLiveFailure.mediaUnavailable);
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
