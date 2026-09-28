// Writes expected.json for the FC2 Live samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.26-fc2live.md, "样本与 v3 的冻结输出").
//
// The archive has no FC2 expected.json (its legacy harness only covered five
// platforms, and 3.x no longer builds). The code below is 3.x's Fc2Api,
// Fc2Link, Fc2Site, Fc2InputRecipe and Fc2ControlSession.parseHlsResponse,
// copied from legacy/lib/core/site/fc2live/ (archive/v4). 3.x already
// injected its transport (`Fc2Request`), so only that function is replaced:
// it answers from the samples by path and form fields, with the status the
// sample recorded, and records every request. A request without a sample
// fails the run (it is recorded under `unmatched` and the run exits with an
// error). The network-only `_defaultRequest` and `_readBody` are left out,
// so the injection point is required. The control session's WebSocket part
// is left out too (it needs a live socket); its message parser runs over the
// recorded `_response_` frame of control/S04-control.
//
// `i18n` is replaced by the Chinese text (3.x's zh.json) of the keys used;
// `extends LiveSite implements …`, the `@override` marks and the danmaku
// getter are left out. Dio's CancelToken and 3.x's `withRequestCancellation`
// (legacy/lib/core/common/request_scope.dart), LiveRoom, LiveArea,
// LiveCategory, LivePlayQuality, LivePlayUrlResolution, LiveDirectoryPage and
// LiveInputRecipe are reduced to the parts these classes use (constructor
// defaults, the mutable fields, the state getters, selectionId, toJson; 3.x's
// toJson wrote the raw `isRecord` field and the normalized `httpHeaders`).
//
// S02-member-offline and S02-member-restricted were recorded for this module
// (2026-09-28, same format): the archive had no existing offline channel and
// no restricted one.
//
// The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`); every call also records the
// requests it sent.
//
// Run from the repository root: dart run fixtures/fc2live/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/fc2live';

const _live = '62996200';

/// Keywords run against the S01 snapshot: a name, a title fragment, the
/// English area name 3.x gave directory cards, a word in many names (two
/// pages), a channel id fragment with a leading zero (not an exact id), and
/// nothing.
const _keywords = ['ちゅうや', '猫', 'idle chat', 'fc2user', '0200', 'zxqvnoresultfixture'];

/// Exact lookups: a live channel by id and by link, and the channels whose
/// member answers were recorded.
const _exact = ['62996200', 'https://live.fc2.com/ja/62996200/', '99999999', '10608314', '3024638'];

/// Inputs of 3.x's `Fc2Link.parseChannelId` (no requests).
const _links = [
  '10608314',
  ' 10608314 ',
  '0',
  '0123',
  '1234567890123',
  'https://live.fc2.com/10608314/',
  'https://live.fc2.com/10608314',
  'http://live.fc2.com/10608314/',
  'https://live.fc2.com/en/10608314/',
  'https://live.fc2.com/JA/10608314/',
  'https://live.fc2.com/xx/10608314/',
  'https://live.fc2.com/10608314/?utm=share',
  'https://live.fc2.com/10608314/#chat',
  'https://LIVE.FC2.COM/10608314/',
  'https://live.fc2.com/',
  'https://live.fc2.com/rank/',
  'https://live.fc2.com/10608314/archive',
  'https://live.fc2.com.evil.test/10608314/',
  'https://user@live.fc2.com/10608314/',
  'https://m.live.fc2.com/10608314/',
  'ftp://live.fc2.com/10608314/',
  'https://live.fc2.com/%E3%81%82/',
];

void main() async {
  await _directory();
  await _member('S02-member-live', _live, grant: true, links: true);
  await _member('S02-member-missing', '99999999');
  await _member('S02-member-offline', '10608314');
  await _member('S02-member-restricted', '3024638', grant: true);
  _controlGrant();
  _hlsResponse();
  if (_misses.isNotEmpty) {
    stderr.writeln('requests without a sample:\n${_misses.join('\n')}');
    exitCode = 1;
  }
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final List<String> _requests = [];
final List<String> _misses = [];

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _replay(List<String> samples) => _samples = [for (final sample in samples) _meta(sample)];

bool _sameForm(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

String _describe(Uri uri, Map<String, String> form) =>
    'POST ${uri.path}${form.isEmpty ? '' : ' ${form.entries.map((e) => '${e.key}=${e.value}').join('&')}'}';

/// 3.x's `Fc2Request` over the samples: by path and form fields.
Future<({int status, String body})> _fixtureRequest(
  Uri uri,
  Map<String, String> headers,
  Map<String, String> form,
  CancelToken cancel,
) async {
  final described = _describe(uri, form);
  _requests.add(described);
  for (final meta in _samples) {
    final request = meta['request'] as Map<String, dynamic>;
    final recorded = Uri.parse(request['url'] as String);
    final body = request['body'] as String? ?? '';
    if (recorded.host == uri.host && recorded.path == uri.path && _sameForm(Uri.splitQueryString(body), form)) {
      final status = (meta['response'] as Map<String, dynamic>)['status'] as int;
      return (status: status, body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync());
    }
  }
  _misses.add(described);
  throw StateError('No recorded sample for $described');
}

Fc2Site _site() => Fc2Site(api: Fc2Api(request: _fixtureRequest));

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
  final result = await _outcome(body, project);
  return {
    'result': result,
    'requests': [..._requests],
  };
}

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString()
    ..['data'] = room.data == null ? null : room.data.runtimeType.toString();
  json.removeWhere(
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

Object? _page(LiveDirectoryPage page) => {'page': page.page, 'hasMore': page.hasMore, 'rooms': _rooms(page.rooms)};

Object? _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data?.toString()},
];

Object? _resolution(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
  'inputRecipe': resolution.inputRecipe?.identity,
};

LiveArea _area(String id) =>
    LiveArea(platform: 'fc2live', areaType: 'public', areaId: id, areaName: id, typeName: 'FC2 Live');

// Samples ---------------------------------------------------------------------

/// `allchannellist.php`: categories, the native directory pages (all rooms
/// and every area), 3.x's slices, the keyword search over the snapshot, the
/// exact lookups (member answers) and the 20 s cache. A call with a cancel
/// token always fetches anew (the directory and search pages pass one);
/// without one the site reuses its snapshot for 20 s, so every call below
/// gets a new Fc2Site and records its own requests, except `cache`.
Future<void> _directory() async {
  _replay(['S01-directory', 'S02-member-live', 'S02-member-missing', 'S02-member-offline', 'S02-member-restricted']);
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
    'getCategores(pageSize: 0)': await _traced(() => _site().getCategores(1, 0), (categories) => categories.length),
  };
  final areas = (await _site().getCategores(1, 30)).single.children;
  final directory = <String, Object?>{};
  for (final page in [1, 2, 3, 4]) {
    directory['recommend:$page'] = await _traced(
      () => _site().getDirectoryPage(page: page, cancel: CancelToken()),
      _page,
    );
  }
  for (final area in areas) {
    for (final page in [1, 2]) {
      directory['${area.areaId}:$page'] = await _traced(
        () => _site().getDirectoryPage(page: page, category: area, cancel: CancelToken()),
        _page,
      );
    }
  }
  directory['recommend:0'] = await _traced(() => _site().getDirectoryPage(page: 0, cancel: CancelToken()), _page);
  directory['3:1'] = await _traced(() => _site().getDirectoryPage(category: _area('3'), cancel: CancelToken()), _page);
  directory['otherPlatform:1'] = await _traced(
    () => _site().getDirectoryPage(
      category: LiveArea(platform: 'bilibili', areaType: 'public', areaId: '1', areaName: 'x'),
      cancel: CancelToken(),
    ),
    _page,
  );
  value['getDirectoryPage'] = directory;
  value['getRecommendRooms'] = {
    for (final (page, size) in [(1, 30), (2, 30), (3, 30), (1, 20), (4, 20), (1, 100), (1, 101), (0, 30), (1, 0)])
      'page $page size $size': await _traced(() => _site().getRecommendRooms(page: page, pageSize: size), _rooms),
  };
  value['getCategoryRooms'] = {
    for (final (id, page, size) in [
      ('all', 1, 30),
      ('1', 1, 30),
      ('1', 2, 20),
      ('2', 1, 30),
      ('4', 1, 30),
      ('9', 1, 30),
      ('5', 1, 30),
      ('3', 1, 30),
      ('1', 1, 101),
    ])
      '$id page $page size $size': await _traced(
        () => _site().getCategoryRooms(_area(id), page: page, pageSize: size),
        _rooms,
      ),
  };
  final search = <String, Object?>{};
  for (final keyword in _keywords) {
    search['$keyword page 1'] = await _traced(
      () => _site().searchRoomsCancellable(keyword, page: 1, pageSize: 20, cancel: CancelToken()),
      _rooms,
    );
  }
  for (final page in [1, 2, 3]) {
    search['fc2user page $page size 5'] = await _traced(
      () => _site().searchRoomsCancellable('fc2user', page: page, pageSize: 5, cancel: CancelToken()),
      _rooms,
    );
  }
  for (final keyword in _exact) {
    search['exact $keyword'] = await _traced(
      () => _site().searchRoomsCancellable(keyword, page: 1, pageSize: 20, cancel: CancelToken()),
      _rooms,
    );
  }
  search['exact 62996200 page 2'] = await _traced(
    () => _site().searchRoomsCancellable('62996200', page: 2, pageSize: 20, cancel: CancelToken()),
    _rooms,
  );
  search['blank'] = await _traced(() => _site().searchRooms('  ', page: 1, pageSize: 20), _rooms);
  search['page 0'] = await _traced(() => _site().searchRooms('猫', page: 0, pageSize: 20), _rooms);
  search['pageSize 101'] = await _traced(() => _site().searchRooms('猫', page: 1, pageSize: 101), _rooms);
  value['searchRooms (pageSize 20)'] = search;
  // The 20 s cache: three calls on one site without a cancel token, then
  // one with a token.
  final cached = _site();
  value['cache'] = await _traced(() async {
    await cached.getRecommendRooms();
    await cached.getCategoryRooms(_area('1'));
    await cached.searchRooms('猫');
    await cached.getDirectoryPage(cancel: CancelToken());
    return true;
  }, (value) => value);
  _write(
    'S01-directory',
    'Fc2Site.getCategores + getDirectoryPage + getRecommendRooms + getCategoryRooms + searchRooms '
        '(exact lookups with the S02 member samples)',
    value,
  );
}

/// A channel's member answer: room entry, refresh, recording, live status,
/// qualities, the play resolution and recovery, and (for [grant]) the
/// control grant with S03-control.
Future<void> _member(String sample, String channelId, {bool grant = false, bool links = false}) async {
  _replay([sample, if (grant) 'S03-control']);
  final site = _site();
  final value = <String, Object?>{
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: channelId, platform: 'fc2live'), _roomProjection),
    'getRoomDetailForRefresh': await _traced(
      () => site.getRoomDetailForRefresh(roomId: channelId, platform: 'fc2live'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _traced(
      () => site.getRoomDetailForRecording(roomId: channelId, platform: 'fc2live'),
      _roomProjection,
    ),
    'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: channelId, platform: 'fc2live'), (live) => live),
    'getRoomDetail(link)': await _traced(
      () => site.getRoomDetail(roomId: 'https://live.fc2.com/$channelId/', platform: 'fc2live'),
      _roomProjection,
    ),
  };
  LiveRoom? detail;
  LiveRoom? refreshed;
  try {
    detail = await site.getRoomDetail(roomId: channelId, platform: 'fc2live');
    refreshed = await site.getRoomDetailForRefresh(roomId: channelId, platform: 'fc2live');
  } on Object {
    detail = null;
  }
  if (detail != null) {
    final room = detail;
    value['getPlayQualites'] = await _traced(() => site.getPlayQualites(detail: room), _qualities);
    final auto = LivePlayQuality(id: 'auto', quality: i18n('fc2live_quality_auto'));
    value['resolvePlayUrlsRaw(auto)'] = await _traced(
      () => site.resolvePlayUrlsRaw(detail: room, quality: auto),
      _resolution,
    );
    value['resolvePlayUrlsRaw(original)'] = await _traced(
      () => site.resolvePlayUrlsRaw(
        detail: room,
        quality: LivePlayQuality(id: 'original', quality: '原画'),
      ),
      _resolution,
    );
    value['resolvePlayUrlsForRecoveryRaw(auto)'] = await _traced(
      () => site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: auto),
      _resolution,
    );
    value['getPlayUrls(auto)'] = await _traced(() => site.getPlayUrls(detail: room, quality: auto), (urls) => urls);
    final card = refreshed;
    if (card != null) {
      value['getPlayQualites(refresh detail)'] = await _traced(() => site.getPlayQualites(detail: card), _qualities);
    }
  }
  if (grant) {
    value['Fc2Api.controlGrant'] = await _traced(
      () => Fc2Api(request: _fixtureRequest).controlGrant(channelId),
      (grant) => {
        'channelId': grant.channelId,
        'webSocket': grant.webSocket.toString(),
        'controlToken': grant.controlToken,
        'orz': grant.orz,
      },
    );
  }
  if (links) {
    value['Fc2Link.parseChannelId'] = {for (final link in _links) link: Fc2Link.parseChannelId(link)};
    value['Fc2Link.channelUrl'] = Fc2Link.channelUrl(channelId);
    value['Fc2Api.mediaHeaders'] = Fc2Api.mediaHeaders(channelId);
    value['Fc2InputRecipe.identity'] = Fc2InputRecipe(channelId).identity;
  }
  _write(
    sample,
    'Fc2Site.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
    'getPlayQualites + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + getPlayUrls'
    '${grant ? ' + Fc2Api.controlGrant (with S03-control)' : ''}'
    '${links ? ' + Fc2Link + Fc2Api.mediaHeaders + Fc2InputRecipe' : ''}',
    value,
  );
}

/// `getControlServer.php` for channel 62996200.
void _controlGrant() {
  final root = jsonDecode(File('$_root/S03-control/body.json').readAsStringSync()) as Map<String, dynamic>;
  Object? parse(String channelId) {
    try {
      final grant = Fc2Api.parseControlGrant(root, expectedChannelId: channelId);
      return {
        'channelId': grant.channelId,
        'webSocket': grant.webSocket.toString(),
        'controlToken': grant.controlToken,
        'orz': grant.orz,
      };
    } on Object catch (error) {
      return _errorProjection(error);
    }
  }

  _write('S03-control', 'Fc2Api.parseControlGrant', {_live: parse(_live), '10608314': parse('10608314')});
}

/// The control socket's `get_hls_information` answer (control/S04-control):
/// the master playlist 3.x played.
void _hlsResponse() {
  final frames = [
    for (final line in File('$_root/control/S04-control/frames.jsonl').readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
  final response = frames
      .where((frame) => frame['dir'] == 'in')
      .map((frame) => jsonDecode(frame['text'] as String) as Map<String, dynamic>)
      .firstWhere((message) => message['name'] == '_response_');
  Object? parse(String channelId) {
    try {
      return Fc2ControlSession.parseHlsResponse(response, expectedChannelId: channelId).toString();
    } on Object catch (error) {
      return _errorProjection(error);
    }
  }

  _write('control/S04-control', 'Fc2ControlSession.parseHlsResponse (the `_response_` frame)', {
    'sent': [
      for (final frame in frames)
        if (frame['dir'] == 'out') frame['text'],
    ],
    _live: parse(_live),
    '10608314': parse('10608314'),
  });
}

// 3.x models (the parts the FC2 classes use) ---------------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

/// Dio's CancelToken, reduced to what 3.x's FC2 code uses.
class CancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancel => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

/// legacy/lib/core/common/request_scope.dart.
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

/// 3.x's zh.json text of the keys the FC2 classes use.
String i18n(String key) => const {
  'fc2live_category_all': '全部公开直播',
  'fc2live_category_chat': '闲聊',
  'fc2live_category_game': '游戏 / 作业',
  'fc2live_category_video': '视频',
  'fc2live_category_audio': '音频',
  'fc2live_category_other': '其他',
  'fc2live_chat_notice': 'FC2 远端聊天尚待接入；媒体控制 WebSocket 由播放或录制独占，并保持到原生输入完整释放。',
  'fc2live_access_restricted': '该 FC2 直播需要登录、积分、门票或付费；界面保留受限状态，不将其显示成未开播。',
  'fc2live_adult_notice': '该房间由平台标记为成人内容，不进入普通公开目录。',
  'fc2live_quality_auto': '自适应 HLS',
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

abstract interface class LiveInputRecipe {
  String get identity;
}

class LivePlayUrlResolution {
  const LivePlayUrlResolution({required this.urls, this.appliedQualityData}) : inputRecipe = null;

  const LivePlayUrlResolution.owned({required LiveInputRecipe input, this.appliedQualityData})
    : inputRecipe = input,
      urls = const [];

  final List<String> urls;
  final Object? appliedQualityData;
  final LiveInputRecipe? inputRecipe;
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

// 3.x's FC2 Live adapter (legacy/lib/core/site/fc2live/) ---------------------
//
// Unchanged apart from the model names above and the transport: no Dio, so
// `CancelToken` is the stub above, and `_defaultRequest` / `_readBody` are
// left out (the request function is required).

// fc2_link.dart
abstract final class Fc2Link {
  static final RegExp _channelId = RegExp(r'^[1-9]\d{0,11}$');
  static const Set<String> _locales = {'en', 'es', 'de', 'fr', 'id', 'ja', 'ko', 'pt', 'ru', 'th', 'tw', 'vi', 'zh'};

  static String channelUrl(String raw) => 'https://live.fc2.com/${requireChannelId(raw)}/';

  static String requireChannelId(String raw) {
    final result = parseChannelId(raw);
    if (result == null) throw const FormatException('Invalid FC2 Live channel identity');
    return result;
  }

  static String? parseChannelId(String raw) {
    final input = raw.trim();
    if (_valid(input)) return input;
    final uri = Uri.tryParse(input);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'live.fc2.com' ||
        uri.hasFragment) {
      return null;
    }
    late final List<String> segments;
    try {
      segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    } on FormatException {
      return null;
    }
    if (segments.length == 1 && _valid(segments.single)) return segments.single;
    if (segments.length == 2 && _locales.contains(segments.first.toLowerCase()) && _valid(segments.last)) {
      return segments.last;
    }
    return null;
  }

  static bool _valid(String value) => _channelId.hasMatch(value);
}

// fc2_input_recipe.dart
final class Fc2InputRecipe implements LiveInputRecipe {
  Fc2InputRecipe(String channelId) : channelId = Fc2Link.requireChannelId(channelId);

  final String channelId;

  @override
  String get identity => 'fc2live:$channelId:auto';
}

// fc2_api.dart
enum Fc2Failure { transport, access, missing, rateLimited, service, schema, identity, cancelled, offline }

final class Fc2Exception implements Exception {
  const Fc2Exception(this.kind);

  final Fc2Failure kind;

  @override
  String toString() => 'FC2 Live ${kind.name}';
}

enum Fc2State { live, offline, restricted }

final class Fc2Room {
  const Fc2Room({
    required this.channelId,
    required this.userName,
    required this.title,
    required this.description,
    required this.cover,
    required this.categoryId,
    required this.categoryName,
    required this.currentViewers,
    required this.totalViewers,
    required this.state,
    required this.isAdult,
    required this.startedAt,
  });

  final String channelId;
  final String userName;
  final String title;
  final String description;
  final String cover;
  final int categoryId;
  final String categoryName;
  final int? currentViewers;
  final int? totalViewers;
  final Fc2State state;
  final bool isAdult;
  final DateTime? startedAt;
}

final class Fc2Directory {
  Fc2Directory({required Iterable<Fc2Room> rooms}) : rooms = List.unmodifiable(rooms);

  final List<Fc2Room> rooms;
}

final class Fc2ControlGrant {
  const Fc2ControlGrant({
    required this.channelId,
    required this.webSocket,
    required this.controlToken,
    required this.orz,
  });

  final String channelId;
  final Uri webSocket;
  final String controlToken;
  final String orz;
}

typedef Fc2Request = Future<({int status, String body})> Function(
  Uri uri,
  Map<String, String> headers,
  Map<String, String> form,
  CancelToken cancel,
);

class Fc2Api {
  Fc2Api({required Fc2Request request, this.deadline = const Duration(seconds: 25)}) : _request = request;

  static const String origin = 'https://live.fc2.com';
  static const int responseLimit = 4 * 1024 * 1024;
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  static const Map<String, String> headers = {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Accept-Language': 'ja,en-US;q=0.9,en;q=0.8',
    'Origin': origin,
    'Referer': '$origin/',
    'X-Requested-With': 'XMLHttpRequest',
  };

  static Map<String, String> mediaHeaders(String channelId) => {
    'User-Agent': userAgent,
    'Origin': origin,
    'Referer': Fc2Link.channelUrl(channelId),
  };

  final Fc2Request _request;
  final Duration deadline;

  Future<T> _scope<T>(CancelToken? caller, Future<T> Function(CancelToken) work) =>
      withRequestCancellation(caller, (transport) async {
        if (transport.isCancelled) throw const Fc2Exception(Fc2Failure.cancelled);
        try {
          return await Future.any<T>([
            work(transport),
            transport.whenCancel.then<T>((_) => throw const Fc2Exception(Fc2Failure.cancelled)),
          ]).timeout(deadline);
        } on TimeoutException {
          throw const Fc2Exception(Fc2Failure.transport);
        } catch (error) {
          if (caller?.isCancelled == true || transport.isCancelled) {
            throw const Fc2Exception(Fc2Failure.cancelled);
          }
          if (error is Fc2Exception) rethrow;
          throw const Fc2Exception(Fc2Failure.transport);
        }
      });

  Future<Map<String, dynamic>> _post(String path, Map<String, String> form, CancelToken token) async {
    final uri = Uri.parse('$origin$path');
    final response = await _request(uri, headers, form, token);
    _throwStatus(response.status);
    if (response.body.length > responseLimit) throw const Fc2Exception(Fc2Failure.schema);
    try {
      return _object(jsonDecode(response.body));
    } on FormatException {
      throw const Fc2Exception(Fc2Failure.schema);
    }
  }

  Future<Fc2Directory> directory({CancelToken? cancel}) => _scope(cancel, (token) async {
    final root = await _post('/contents/allchannellist.php', const {}, token);
    return parseDirectory(root);
  });

  Future<Fc2Room> room(String rawChannelId, {CancelToken? cancel}) => _scope(cancel, (token) async {
    final channelId = Fc2Link.parseChannelId(rawChannelId);
    if (channelId == null) throw const Fc2Exception(Fc2Failure.identity);
    final root = await _member(channelId, token);
    return parseMember(root, expectedChannelId: channelId).room;
  });

  Future<Fc2ControlGrant> controlGrant(String rawChannelId, {CancelToken? cancel}) => _scope(cancel, (token) async {
    final channelId = Fc2Link.parseChannelId(rawChannelId);
    if (channelId == null) throw const Fc2Exception(Fc2Failure.identity);
    final member = parseMember(await _member(channelId, token), expectedChannelId: channelId);
    if (member.room.state == Fc2State.offline) throw const Fc2Exception(Fc2Failure.offline);
    if (member.room.state == Fc2State.restricted) throw const Fc2Exception(Fc2Failure.access);
    final root = await _post('/api/getControlServer.php', {
      'channel_id': channelId,
      'mode': 'play',
      'orz': '',
      'channel_version': member.version,
      'client_version': '2.1.0\n [1]',
      'client_type': 'pc',
      'client_app': 'browser_hls',
      'ipv6': '',
    }, token);
    return parseControlGrant(root, expectedChannelId: channelId);
  });

  Future<Map<String, dynamic>> _member(String channelId, CancelToken token) =>
      _post('/api/memberApi.php', {'channel': '1', 'profile': '1', 'user': '1', 'streamid': channelId}, token);

  static Fc2Directory parseDirectory(Map<String, dynamic> root) {
    _positiveInt(root['time']);
    final seen = <String>{};
    final rooms = <Fc2Room>[];
    for (final value in _list(root['channel'], max: 1000)) {
      final data = _object(value);
      // Open chat and private two-shot entries are not public media rooms.
      if (_int(data['type']) != 1) continue;
      final room = _directoryRoom(data);
      if (seen.add(room.channelId)) rooms.add(room);
    }
    return Fc2Directory(rooms: rooms);
  }

  static Fc2Room _directoryRoom(Map<String, dynamic> data) {
    final id = _channelId(data['id']);
    final restricted = _int(data['pay']) != 0 || _int(data['login']) != 0 || _int(data['tid']) != 0;
    final categoryId = _boundedInt(data['category'], min: 0, max: 99);
    return Fc2Room(
      channelId: id,
      userName: _firstText([data['name'], id]),
      title: _firstText([data['title'], data['name'], id]),
      description: '',
      cover: _image(data['image']),
      categoryId: categoryId,
      categoryName: categoryName(categoryId),
      currentViewers: _nonNegativeInt(data['count']),
      totalViewers: _nonNegativeInt(data['total']),
      state: restricted ? Fc2State.restricted : Fc2State.live,
      isAdult: false,
      startedAt: _epochMillis(data['start_time']),
    );
  }

  static ({Fc2Room room, String version}) parseMember(Map<String, dynamic> root, {required String expectedChannelId}) {
    if (_int(root['status']) != 1) throw const Fc2Exception(Fc2Failure.missing);
    final data = _object(root['data']);
    final channel = _object(data['channel_data']);
    final profile = _optionalObject(data['profile_data']);
    final id = _channelId(channel['channelid']);
    if (id != expectedChannelId) throw const Fc2Exception(Fc2Failure.identity);
    final published = _int(channel['is_publish']) == 1;
    final restricted =
        _int(channel['fee']) != 0 ||
        _int(channel['login_only']) != 0 ||
        _int(channel['ticketid']) != 0 ||
        _int(channel['ticket_only']) != 0 ||
        _int(channel['is_limited']) != 0;
    final categoryId = _boundedInt(channel['category'], min: 0, max: 99);
    final version = _boundedToken(channel['version'], max: 256);
    return (
      room: Fc2Room(
        channelId: id,
        userName: _firstText([profile?['name'], channel['tname'], id]),
        title: _firstText([channel['title'], profile?['name'], id]),
        description: _optionalText(channel['info']),
        cover: _image(channel['image']),
        categoryId: categoryId,
        categoryName: _firstOptionalText([channel['category_name'], categoryName(categoryId)]),
        currentViewers: _nonNegativeInt(channel['count']),
        totalViewers: _nonNegativeInt(channel['total']),
        state: !published
            ? Fc2State.offline
            : restricted
            ? Fc2State.restricted
            : Fc2State.live,
        isAdult: _int(channel['adult']) == 1,
        startedAt: _epochMillis(channel['start']),
      ),
      version: version,
    );
  }

  static Fc2ControlGrant parseControlGrant(Map<String, dynamic> root, {required String expectedChannelId}) {
    final status = _int(root['status']);
    if (status != 0) throw const Fc2Exception(Fc2Failure.offline);
    final rawUri = _boundedToken(root['url'], max: 2048);
    final token = _boundedToken(root['control_token'], max: 4096);
    final orz = _boundedToken(root['orz_raw'], max: 256);
    final uri = Uri.tryParse(rawUri);
    if (uri == null ||
        uri.scheme != 'wss' ||
        uri.userInfo.isNotEmpty ||
        !_isFc2Host(uri.host) ||
        uri.path != '/control/channels/$expectedChannelId' ||
        uri.hasQuery ||
        uri.hasFragment ||
        !RegExp(r'^[A-Za-z0-9._~-]+$').hasMatch(orz)) {
      throw const Fc2Exception(Fc2Failure.schema);
    }
    return Fc2ControlGrant(channelId: expectedChannelId, webSocket: uri, controlToken: token, orz: orz);
  }

  static String categoryName(int category) => switch (category) {
    1 => 'Idle Chat',
    2 || 3 => 'Game / Work',
    4 => 'Video',
    5 => 'Other',
    9 => 'Audio',
    _ => 'FC2 Live',
  };

  static bool _isFc2Host(String host) {
    final value = host.toLowerCase();
    return value == 'live.fc2.com' || value.endsWith('.live.fc2.com');
  }

  static String _channelId(Object? value) {
    final result = Fc2Link.parseChannelId(_text(value));
    if (result == null) throw const Fc2Exception(Fc2Failure.schema);
    return result;
  }

  static String _image(Object? value) {
    final raw = _optionalText(value);
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !(uri.host.toLowerCase() == 'fc2.com' || uri.host.toLowerCase().endsWith('.fc2.com'))) {
      return '';
    }
    return uri.toString();
  }

  static DateTime? _epochMillis(Object? value) {
    final millis = switch (value) {
      int number => number,
      num number when number.isFinite => number.toInt(),
      String text => int.tryParse(text.trim()),
      _ => null,
    };
    if (millis == null || millis < 946684800000 || millis > 4102444800000) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  static String _boundedToken(Object? value, {required int max}) {
    final result = _text(value);
    if (result.length > max) throw const Fc2Exception(Fc2Failure.schema);
    return result;
  }

  static int _boundedInt(Object? value, {required int min, required int max}) {
    final result = _int(value);
    if (result < min || result > max) throw const Fc2Exception(Fc2Failure.schema);
    return result;
  }

  static int _positiveInt(Object? value) {
    final result = _int(value);
    if (result < 1) throw const Fc2Exception(Fc2Failure.schema);
    return result;
  }

  static int _int(Object? value) {
    final result = switch (value) {
      int number => number,
      num number when number.isFinite => number.toInt(),
      String text => int.tryParse(text.trim()),
      _ => null,
    };
    if (result == null || result < -0x7fffffff || result > 0x7fffffff) {
      throw const Fc2Exception(Fc2Failure.schema);
    }
    return result;
  }

  static int? _nonNegativeInt(Object? value) {
    if (value == null) return null;
    final result = _int(value);
    return result >= 0 ? result : null;
  }

  static String _text(Object? value) {
    final result = _optionalText(value);
    if (result.isEmpty) throw const Fc2Exception(Fc2Failure.schema);
    return result;
  }

  static String _firstText(Iterable<Object?> values) {
    final result = _firstOptionalText(values);
    if (result.isEmpty) throw const Fc2Exception(Fc2Failure.schema);
    return result;
  }

  static String _firstOptionalText(Iterable<Object?> values) {
    for (final value in values) {
      final result = _optionalText(value);
      if (result.isNotEmpty) return result;
    }
    return '';
  }

  static String _optionalText(Object? value) {
    if (value == null) return '';
    if (value is! String) throw const Fc2Exception(Fc2Failure.schema);
    final result = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (result.length > 65536) throw const Fc2Exception(Fc2Failure.schema);
    return result;
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const Fc2Exception(Fc2Failure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static Map<String, dynamic>? _optionalObject(Object? value) => value == null ? null : _object(value);

  static List<Object?> _list(Object? value, {required int max}) {
    if (value is! List || value.length > max) throw const Fc2Exception(Fc2Failure.schema);
    return value;
  }

  static void _throwStatus(int status) {
    final failure = switch (status) {
      200 => null,
      400 || 422 => Fc2Failure.schema,
      401 || 403 => Fc2Failure.access,
      404 => Fc2Failure.missing,
      429 => Fc2Failure.rateLimited,
      >= 500 => Fc2Failure.service,
      _ => Fc2Failure.transport,
    };
    if (failure != null) throw Fc2Exception(failure);
  }
}

// fc2_control_session.dart: the message parser only (the session needs a
// live WebSocket).
abstract final class Fc2ControlSession {
  static Uri parseHlsResponse(Map<String, dynamic> response, {required String expectedChannelId}) {
    if (response['name'] != '_response_' || response['id'] != 1) {
      throw const Fc2Exception(Fc2Failure.schema);
    }
    final arguments = _object(response['arguments']);
    if (_integer(arguments['status']) != 0) throw const Fc2Exception(Fc2Failure.access);
    final playlists = _list(arguments['playlists'], max: 32);
    for (final value in playlists) {
      final item = _object(value);
      if (_integer(item['mode']) != 0 || _integer(item['status']) != 0) continue;
      final uri = Uri.tryParse(_string(item['url']));
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.userInfo.isNotEmpty ||
          !_isMediaHost(uri.host) ||
          uri.path != '/a/stream/$expectedChannelId/0/master_playlist' ||
          uri.hasFragment ||
          !_token(uri.queryParameters['c']) ||
          !_token(uri.queryParameters['d']) ||
          !_targets(uri.queryParameters['targets']) ||
          uri.queryParameters.keys.any((key) => !const {'targets', 'c', 'd'}.contains(key))) {
        throw const Fc2Exception(Fc2Failure.schema);
      }
      return uri;
    }
    throw const Fc2Exception(Fc2Failure.schema);
  }

  static bool _isMediaHost(String host) {
    final value = host.toLowerCase();
    return value == 'live.fc2.com' || value.endsWith('.live.fc2.com');
  }

  static bool _token(String? value) => value != null && value.isNotEmpty && value.length <= 1024;

  static bool _targets(String? value) =>
      value != null &&
      value.isNotEmpty &&
      value.length <= 128 &&
      RegExp(r'^\d{1,3}(?:,\d{1,3}){0,15}$').hasMatch(value);

  static int _integer(Object? value) {
    final result = switch (value) {
      int number => number,
      num number when number.isFinite => number.toInt(),
      String text => int.tryParse(text.trim()),
      _ => null,
    };
    if (result == null) throw const Fc2Exception(Fc2Failure.schema);
    return result;
  }

  static String _string(Object? value) {
    if (value is! String || value.isEmpty || value.length > 65536) {
      throw const Fc2Exception(Fc2Failure.schema);
    }
    return value;
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const Fc2Exception(Fc2Failure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<Object?> _list(Object? value, {required int max}) {
    if (value is! List || value.length > max) throw const Fc2Exception(Fc2Failure.schema);
    return value;
  }
}

// fc2_site.dart
final class Fc2Site {
  Fc2Site({Fc2Api? api}) : _api = api ?? Fc2Api(request: _fixtureRequest);

  final Fc2Api _api;
  Future<Fc2Directory>? _directoryRequest;
  DateTime? _directoryAt;

  String get id => 'fc2live';

  String get name => 'FC2 Live';

  String get directoryNoticeKey => 'fc2live_directory_scope';

  Future<Fc2Directory> _directory({CancelToken? cancel}) {
    if (cancel != null) return _api.directory(cancel: cancel);
    final now = DateTime.now();
    final cached = _directoryRequest;
    if (cached != null && _directoryAt != null && now.difference(_directoryAt!) < const Duration(seconds: 20)) {
      return cached;
    }
    late final Future<Fc2Directory> request;
    request = _api
        .directory()
        .then((value) {
          _directoryAt = DateTime.now();
          return value;
        })
        .catchError((Object error) {
          if (identical(_directoryRequest, request)) {
            _directoryRequest = null;
            _directoryAt = null;
          }
          throw error;
        });
    return _directoryRequest = request;
  }

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    if (page != 1 || pageSize < 1) return [];
    LiveArea area(String value, String label) =>
        LiveArea(platform: id, areaType: 'public', areaId: value, areaName: label, typeName: name);
    return [
      LiveCategory(
        id: id,
        name: name,
        children: [
          area('all', i18n('fc2live_category_all')),
          area('1', i18n('fc2live_category_chat')),
          area('2', i18n('fc2live_category_game')),
          area('4', i18n('fc2live_category_video')),
          area('9', i18n('fc2live_category_audio')),
          area('5', i18n('fc2live_category_other')),
        ],
      ),
    ];
  }

  int? _category(LiveArea? category) {
    if (category == null) return null;
    if (category.platform != id || category.areaType != 'public') {
      throw const Fc2Exception(Fc2Failure.identity);
    }
    final areaId = category.areaId;
    if (areaId == 'all') return null;
    final value = areaId == null ? null : int.tryParse(areaId);
    if (!const {1, 2, 4, 5, 9}.contains(value)) throw const Fc2Exception(Fc2Failure.identity);
    return value;
  }

  static bool _matchesCategory(Fc2Room room, int? category) =>
      category == null || room.categoryId == category || (category == 2 && room.categoryId == 3);

  static List<T> _page<T>(List<T> values, int page, int pageSize) {
    if (page < 1 || pageSize < 1 || pageSize > 100) return [];
    final start = (page - 1) * pageSize;
    if (start >= values.length) return [];
    return values.sublist(start, (start + pageSize).clamp(0, values.length));
  }

  static LiveRoom _room(Fc2Room room, {required bool includeMedia}) {
    final liveStatus = switch (room.state) {
      Fc2State.live => LiveStatus.live,
      Fc2State.offline => LiveStatus.offline,
      Fc2State.restricted => LiveStatus.unknown,
    };
    final viewers = room.currentViewers?.toString();
    return LiveRoom(
      platform: 'fc2live',
      roomId: room.channelId,
      userId: room.channelId,
      title: room.title,
      nick: room.userName,
      avatar: room.cover,
      cover: room.cover,
      area: room.categoryName,
      link: Fc2Link.channelUrl(room.channelId),
      liveStatus: liveStatus,
      watching: viewers ?? '',
      onlineViewers: viewers,
      totalViewers: room.totalViewers?.toString(),
      audienceMetricType: viewers == null ? AudienceMetricType.unknown : AudienceMetricType.onlineViewers,
      notice: room.state == Fc2State.restricted
          ? i18n('fc2live_access_restricted')
          : room.isAdult
          ? i18n('fc2live_adult_notice')
          : i18n('fc2live_chat_notice'),
      httpHeaders: Fc2Api.mediaHeaders(room.channelId),
      data: includeMedia && liveStatus == LiveStatus.live ? room : null,
    );
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) throw const Fc2Exception(Fc2Failure.schema);
    final categoryId = _category(category);
    final all = (await _directory(cancel: cancel)).rooms.where((room) => _matchesCategory(room, categoryId)).toList();
    const size = 20;
    return LiveDirectoryPage(
      rooms: _page(all, page, size).map((room) => _room(room, includeMedia: false)),
      page: page,
      hasMore: page * size < all.length,
    );
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async => _page(
    (await _directory()).rooms,
    page,
    pageSize,
  ).map((room) => _room(room, includeMedia: false)).toList(growable: false);

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final categoryId = _category(category);
    final rooms = (await _directory()).rooms.where((room) => _matchesCategory(room, categoryId)).toList();
    return _page(rooms, page, pageSize).map((room) => _room(room, includeMedia: false)).toList(growable: false);
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
    final exactId = Fc2Link.parseChannelId(raw);
    if (exactId != null) {
      if (page != 1) return [];
      try {
        return [_room(await _api.room(exactId, cancel: cancel), includeMedia: false)];
      } on Fc2Exception catch (error) {
        if (error.kind == Fc2Failure.missing) return [];
        rethrow;
      }
    }
    final query = raw.toLowerCase();
    final matches = (await _directory(cancel: cancel)).rooms
        .where(
          (room) =>
              room.channelId.contains(query) ||
              room.userName.toLowerCase().contains(query) ||
              room.title.toLowerCase().contains(query) ||
              room.categoryName.toLowerCase().contains(query),
        )
        .toList();
    return _page(matches, page, pageSize).map((room) => _room(room, includeMedia: false)).toList(growable: false);
  }

  String _identity(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const Fc2Exception(Fc2Failure.identity);
    final channelId = Fc2Link.parseChannelId(roomId);
    if (channelId == null) throw const Fc2Exception(Fc2Failure.identity);
    return channelId;
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia}) async =>
      _room(await _api.room(_identity(roomId, platform)), includeMedia: includeMedia);

  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: true);

  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: false);

  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      _detail(roomId, platform, includeMedia: true);

  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId, platform: platform);
    if (room.effectiveLiveStatus == LiveStatus.unknown) throw const Fc2Exception(Fc2Failure.access);
    return room.isLiveNow;
  }

  Fc2Room _snapshot(LiveRoom detail) {
    final channelId = _identity(detail.roomId ?? '', detail.platform ?? '');
    final room = detail.data;
    if (detail.effectiveLiveStatus != LiveStatus.live || room is! Fc2Room || room.channelId != channelId) {
      throw const Fc2Exception(Fc2Failure.schema);
    }
    return room;
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.isExplicitlyOfflineNow) return const [];
    _snapshot(detail);
    return [LivePlayQuality(id: 'auto', quality: i18n('fc2live_quality_auto'))];
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final room = _snapshot(detail);
    if (quality.selectionId != 'auto') throw const Fc2Exception(Fc2Failure.schema);
    return LivePlayUrlResolution.owned(input: Fc2InputRecipe(room.channelId), appliedQualityData: 'auto');
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => resolvePlayUrlsRaw(detail: detail, quality: quality);

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    await resolvePlayUrlsRaw(detail: detail, quality: quality);
    return const [];
  }
}
