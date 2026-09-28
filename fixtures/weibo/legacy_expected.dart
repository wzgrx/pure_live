// Writes expected.json for the Weibo samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.18-weibo.md, "样本与 v3 的冻结输出").
//
// The archive has no Weibo expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below is 3.x's
// WeiboApi, WeiboLink and WeiboSite, copied from
// legacy/lib/core/site/weibo/weibo_api.dart, weibo_link.dart and
// weibo_site.dart (archive/v4), and `withRequestCancellation` from
// legacy/lib/core/common/request_scope.dart. 3.x already injected its
// transport (`WeiboRequest`), so only that function is replaced: it answers
// from the samples by host, path and query, like the legacy FixtureAdapter,
// with the empty body 3.x read for any status other than 200, and throws a
// StateError for a request without a sample (rethrown by `_scope`, so a
// harness miss is never recorded as 3.x's transport failure). The injection
// point is therefore required, and the network-only `_defaultRequest` and
// `readBody` are left out. `i18n` is replaced by the Chinese text (3.x's
// zh.json) of the keys used; `extends LiveSite implements …`, the
// `@override` marks and the danmaku getter are left out. Dio's CancelToken,
// 3.x's LiveRoom, LiveArea, LiveCategory, LivePlayQuality,
// LivePlayUrlResolution and LiveDirectoryPage are reduced to the parts these
// classes use (constructor defaults, the mutable fields, isLiveNow,
// selectionId, toJson; 3.x's toJson wrote the raw `isRecord` field).
//
// S01-recommend was recorded by the archive with `count=100`; 3.x asked for
// `count=10` (S03-recommend is that request). For S01 the harness answers
// 3.x's request from the recording whatever its `count` (3.x's parser does
// not read it), so the parser runs over all 51 rows.
//
// The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`); every call also records the
// requests it sent.
//
// Run from the repository root: dart run fixtures/weibo/legacy_expected.dart
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/weibo';

/// Keywords run against the recommendation snapshots: one match (卫视, 学长,
/// 发布), letters in another case (vortex, bang), many matches (_, 小),
/// spaces around the keyword, and none.
const _keywords = ['卫视', '学长', '发布', 'vortex', 'bang', '_', '小', ' 卫视 ', 'zxqvnoresultfixture'];

void main() async {
  await _directory('S01-recommend', ignoreCount: true);
  await _directory('S03-recommend');
  for (final (sample, id) in [
    ('S02-live', '1022:2321325347923495092258'),
    ('S02-watch-limit', '1022:2321325347904448757771'),
    ('S02-ended-replay', '1022:2321325269875509035102'),
    ('S02-notfound', '1022:2321320000000000000001'),
    ('S02-ended', '1022:2320508a306db1bc389510651e77d5feb4f90d'),
    ('S03-live', '1022:2321325348206094712906'),
  ]) {
    await _detail(sample, id);
  }
  if (_misses.isNotEmpty) {
    stderr.writeln('requests without a sample:\n${_misses.join('\n')}');
    exitCode = 1;
  }
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
bool _ignoreCount = false;
final List<Uri> _requests = [];
final List<String> _misses = [];

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _replay(List<String> samples, {bool ignoreCount = false}) {
  _samples = [for (final sample in samples) _meta(sample)];
  _ignoreCount = ignoreCount;
  _requests.clear();
}

bool _sameQuery(Map<String, String> a, Map<String, String> b) {
  Map<String, String> strip(Map<String, String> query) =>
      _ignoreCount ? ({...query}..remove('count')) : query;
  final left = strip(a);
  final right = strip(b);
  return left.length == right.length && left.entries.every((entry) => right[entry.key] == entry.value);
}

/// 3.x's `WeiboRequest` over the samples: 3.x read no body for a status
/// other than 200.
Future<({int status, String body})> _fixtureRequest(
  String method,
  Uri uri,
  Map<String, String>? form,
  CancelToken cancel,
) async {
  _requests.add(uri);
  for (final meta in _samples) {
    final request = meta['request'] as Map;
    final recorded = Uri.parse(request['url'] as String);
    if (request['method'] == method &&
        recorded.host == uri.host &&
        recorded.path == uri.path &&
        _sameQuery(recorded.queryParameters, uri.queryParameters)) {
      final status = (meta['response'] as Map)['status'] as int;
      if (status != 200) return (status: status, body: '');
      return (status: 200, body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync());
    }
  }
  _misses.add('$method $uri');
  throw StateError('No recorded sample for $method $uri');
}

WeiboSite _site() => WeiboSite(api: WeiboApi(request: _fixtureRequest));

List<String> _sent() => [for (final uri in _requests) uri.toString()];

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

Future<Object?> _outcome<T>(FutureOr<T> Function() body, Object? Function(T value) project) async {
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
  return {'result': result, 'requests': _sent()};
}

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere((key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty));
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

Object? _page(LiveDirectoryPage page) => {'rooms': _rooms(page.rooms), 'page': page.page, 'hasMore': page.hasMore};

Object? _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities) {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort},
];

Object? _resolution(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
};

// Samples ---------------------------------------------------------------------

/// `pc_recommend`: the catalog, the native page, 3.x's list calls and the
/// nickname search over the snapshot.
Future<void> _directory(String sample, {bool ignoreCount = false}) async {
  _replay([sample], ignoreCount: ignoreCount);
  final site = _site();
  final categories = await site.getCategores(1, 30);
  final area = categories.single.children.single;
  final value = <String, Object?>{
    'getCategores': [
      for (final category in categories)
        {
          'id': category.id,
          'name': category.name,
          'children': [for (final area in category.children) area.toJson()],
        },
    ],
    'getCategores(page: 2)': (await site.getCategores(2, 30)).length,
    'getDirectoryPage': await _traced(() => site.getDirectoryPage(), _page),
    'getDirectoryPage(page: 2)': await _traced(() => site.getDirectoryPage(page: 2), _page),
    'getDirectoryPage(category)': await _traced(() => site.getDirectoryPage(category: area), _page),
    'getRecommendRooms': {
      for (final (page, size) in [(1, 30), (1, 3), (2, 3)])
        'page $page, pageSize $size': await _traced(() => site.getRecommendRooms(page: page, pageSize: size), _rooms),
    },
    'getCategoryRooms': {
      for (final (page, size) in [(1, 30), (2, 30)])
        'page $page, pageSize $size': await _traced(
          () => site.getCategoryRooms(area, page: page, pageSize: size),
          _rooms,
        ),
    },
    'searchRooms': {
      for (final keyword in _keywords) keyword: await _traced(() => site.searchRooms(keyword, pageSize: 20), _rooms),
      '_ pageSize 3': await _traced(() => site.searchRooms('_', pageSize: 3), _rooms),
      '小 page 2': await _traced(() => site.searchRooms('小', page: 2), _rooms),
      'https://weibo.com/u/101': await _traced(() => site.searchRooms('https://weibo.com/u/101'), _rooms),
      'Re:Zero': await _traced(() => site.searchRooms('Re:Zero'), _rooms),
      '': await _traced(() => site.searchRooms('  '), _rooms),
    },
  };
  _write(
    sample,
    'WeiboSite.getCategores + getDirectoryPage + getRecommendRooms + getCategoryRooms + searchRooms'
        '${ignoreCount ? ' (3.x asked count=10; answered from this count=100 recording)' : ''}',
    value,
  );
}

/// `show_pc_live`: room entry, refresh, recording, exact search, live
/// status, the room link, qualities and URLs (S03-recommend answers the
/// nickname filter 3.x falls back to for an id it rejects).
Future<void> _detail(String sample, String id) async {
  _replay([sample, 'S03-recommend']);
  final site = _site();
  final link = 'https://weibo.com/l/wblive/p/show/$id';
  final mobile = 'https://weibo.com/l/wblive/m/show/${id.replaceAll(':', '%3A')}';
  final value = <String, Object?>{
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: id, platform: 'weibo'), _roomProjection),
    'getRoomDetailForRefresh': await _traced(
      () => site.getRoomDetailForRefresh(roomId: id, platform: 'weibo'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _traced(
      () => site.getRoomDetailForRecording(roomId: id, platform: 'weibo'),
      _roomProjection,
    ),
    'searchRooms': await _traced(() => site.searchRooms(id), _rooms),
    'searchRooms(link)': await _traced(() => site.searchRooms(link), _rooms),
    'searchRooms(mobile link)': await _traced(() => site.searchRooms(mobile), _rooms),
    'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: id, platform: 'weibo'), (live) => live),
    'WeiboLink.parse': {
      for (final input in [id, link, mobile]) input: await _outcome(() => WeiboLink.parse(input), (id) => id),
    },
    'WeiboLink.url': await _outcome(() => WeiboLink.url(id), (url) => url),
  };
  try {
    final detail = await site.getRoomDetail(roomId: id, platform: 'weibo');
    value['getPlayQualites'] = await _outcome(() => site.getPlayQualites(detail: detail), _qualities);
    final original = LivePlayQuality(id: 'original', quality: '原始流', data: _WeiboChoice(id, int.parse(detail.userId!)));
    final qualities = await site.getPlayQualites(detail: detail).catchError((_) => <LivePlayQuality>[]);
    final quality = qualities.isEmpty ? original : qualities.single;
    value['getPlayUrls'] = await _traced(() => site.getPlayUrls(detail: detail, quality: quality), (urls) => urls);
    value['resolvePlayUrlsRaw'] = await _traced(
      () => site.resolvePlayUrlsRaw(detail: detail, quality: quality),
      _resolution,
    );
    value['resolvePlayUrlsForRecoveryRaw'] = await _traced(
      () => site.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: quality),
      _resolution,
    );
  } on Object catch (error) {
    value['getPlayQualites'] = _errorProjection(error);
  }
  _write(
    sample,
    'WeiboSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + searchRooms + getLiveStatus + '
        'WeiboLink.parse + WeiboLink.url + getPlayQualites + getPlayUrls + resolvePlayUrlsRaw + '
        'resolvePlayUrlsForRecoveryRaw (with S03-recommend)',
    value,
  );
}

// Stubs -----------------------------------------------------------------------

/// 3.x's zh.json text of the keys the Weibo classes use.
String i18n(String key) => switch (key) {
  'site_weibo' => '微博直播',
  'weibo_public_directory' => '公开推荐',
  'weibo_room_scope' => '收藏跟踪当前直播场次，不是主播账号；新场次需重新导入直播链接。',
  'weibo_restricted' => '当前场次存在访问限制或播放已关闭；公开直播源不可用。',
  'weibo_original_stream' => '原始流',
  _ => throw StateError('no text for $key'),
};

class CancelToken {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;

  Future<void> get whenCancel => _cancelled.future;

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

// 3.x's request_scope.dart ----------------------------------------------------

/// Owns cancellation for a single request and the consumption of its body.
/// Dio 5.11.1's transformed response stream does not forward subscription
/// cancellation upstream. Ending this scope also stops that upstream source
/// and its receive timer, without cancelling a shared caller token or Dio.
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

// 3.x models (the parts the Weibo classes use) ---------------------------------

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

// 3.x's weibo_api.dart ----------------------------------------------------------

enum WeiboFailure {
  transport,
  access,
  missing,
  rateLimited,
  service,
  api,
  schema,
  identity,
  cancelled,
  notLive,
  mediaUnavailable,
  unknownState,
}

enum WeiboAccess { public, restricted, disabled }

enum WeiboBroadcastState { live, replay, unknown }

class WeiboException implements Exception {
  const WeiboException(this.kind);
  final WeiboFailure kind;
  @override
  String toString() => 'Weibo ${kind.name}';
}

class WeiboDirectoryCard {
  const WeiboDirectoryCard({required this.liveId, required this.ownerId, required this.nickname, required this.cover});
  final String liveId;
  final int ownerId;
  final String nickname;
  final String? cover;
}

/// Declared metadata, not a guarantee of playable media or a stable owner room.
/// A live ID identifies a broadcast; user UID remains separate.
class WeiboLiveDetail {
  const WeiboLiveDetail({
    required this.liveId,
    required this.ownerId,
    required this.title,
    required this.nickname,
    required this.cover,
    required this.avatar,
    required this.access,
    required this.state,
    required this.reportedStatus,
    required this.watchLimit,
    required this.payLiveStatus,
    required this.width,
    required this.height,
    required this.mediaUrls,
  });
  final String liveId;
  final int ownerId;
  final String title;
  final String nickname;
  final String? cover;
  final String? avatar;
  final WeiboAccess access;
  final WeiboBroadcastState state;
  final int reportedStatus;
  final int watchLimit;
  final int payLiveStatus;
  final int width;
  final int height;
  // HLS-labelled fields can contain FLV. Preserve URLs without fabricating quality.
  // No media URLs escape this metadata layer for restricted, disabled or replay states.
  final List<String> mediaUrls;
}

typedef WeiboRequest = Future<({int status, String body})> Function(
  String method,
  Uri uri,
  Map<String, String>? form,
  CancelToken cancel,
);

class WeiboApi {
  WeiboApi({required WeiboRequest request, this.deadline = const Duration(seconds: 20)}) : _request = request;
  static const origin = 'https://weibo.com';
  static const headers = {'Referer': 'https://weibo.com/l/wblive/', 'User-Agent': 'Mozilla/5.0'};
  static const responseLimit = 1024 * 1024;
  final WeiboRequest _request;
  final Duration deadline;

  Future<T> _scope<T>(CancelToken? caller, Future<T> Function(CancelToken) work) =>
      withRequestCancellation(caller, (transport) async {
        if (transport.isCancelled) throw const WeiboException(WeiboFailure.cancelled);
        try {
          return await Future.any<T>([
            work(transport),
            transport.whenCancel.then<T>((_) => throw const WeiboException(WeiboFailure.cancelled)),
          ]).timeout(deadline);
        } on TimeoutException {
          throw const WeiboException(WeiboFailure.transport);
        } catch (error) {
          if (caller?.isCancelled == true) throw const WeiboException(WeiboFailure.cancelled);
          if (error is WeiboException) rethrow;
          // The harness has no network: a request without a sample is a
          // harness error, not 3.x's transport failure.
          if (error is StateError) rethrow;
          throw const WeiboException(WeiboFailure.transport);
        }
      });

  Future<Map<String, dynamic>> _read(String path, CancelToken cancel, {Map<String, String>? form}) async {
    if (cancel.isCancelled) throw const WeiboException(WeiboFailure.cancelled);
    final response = await _request(form == null ? 'GET' : 'POST', Uri.parse('$origin$path'), form, cancel);
    if (cancel.isCancelled) throw const WeiboException(WeiboFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      401 || 403 => WeiboFailure.access,
      404 => WeiboFailure.missing,
      429 => WeiboFailure.rateLimited,
      >= 500 => WeiboFailure.service,
      _ => WeiboFailure.transport,
    };
    if (failure != null) throw WeiboException(failure);
    if (response.body.length > responseLimit || utf8.encode(response.body).length > responseLimit) {
      throw const WeiboException(WeiboFailure.schema);
    }
    try {
      return _object(jsonDecode(response.body));
    } on FormatException {
      throw const WeiboException(WeiboFailure.schema);
    }
  }

  /// Finite anonymous recommendation snapshot, not search or a pagination API.
  Future<List<WeiboDirectoryCard>> directory({CancelToken? cancel}) => _scope(
    cancel,
    (token) async => parseDirectory(await _read('/l/!/2/wblive/pc_recommend/list.json?count=10&uid=', token)),
  );

  Future<WeiboLiveDetail> detail(String liveId, {int? expectedOwnerId, CancelToken? cancel}) {
    validateLiveId(liveId);
    if (expectedOwnerId != null) _owner(expectedOwnerId);
    return _scope(
      cancel,
      (token) async => parseDetail(
        await _read('/l/!/2/wblive/room/show_pc_live.json?live_id=${Uri.encodeQueryComponent(liveId)}', token),
        expectedLiveId: liveId,
        expectedOwnerId: expectedOwnerId,
      ),
    );
  }

  static String validateLiveId(String value) {
    // Both identifiers occur on official indexed watch pages. Neither is a UID.
    if (!RegExp(r'^(?:1022:232132[0-9]{16}|1042152:[0-9a-f]{32})$').hasMatch(value)) {
      throw const WeiboException(WeiboFailure.identity);
    }
    return value;
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) throw const WeiboException(WeiboFailure.schema);
    return value;
  }

  static String _text(Object? value) {
    if (value is! String) throw const WeiboException(WeiboFailure.schema);
    return value;
  }

  static int _number(Object? value) {
    if (value is! int || value < 0) throw const WeiboException(WeiboFailure.schema);
    return value;
  }

  static int _owner(Object? value) {
    if (value is! int || value < 1 || value > 9007199254740991) throw const WeiboException(WeiboFailure.identity);
    return value;
  }

  static int _binary(Object? value) {
    final result = _number(value);
    if (result > 1) throw const WeiboException(WeiboFailure.schema);
    return result;
  }

  static String? _image(Object? value) {
    if (value == null || value == '') return null;
    return _url(value);
  }

  static String _url(Object? value) {
    final text = _text(value);
    final uri = Uri.tryParse(text);
    if (text.trim() != text ||
        RegExp(r'[\\\s]').hasMatch(text) ||
        uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const WeiboException(WeiboFailure.schema);
    }
    return text;
  }

  static Map<String, dynamic> _success(Map<String, dynamic> json) {
    final code = _number(json['code']);
    final error = _number(json['error_code']);
    if (code != 100000 || error != 0) throw const WeiboException(WeiboFailure.api);
    return _object(json['data']);
  }

  static List<WeiboDirectoryCard> parseDirectory(Map<String, dynamic> json) {
    final rows = _success(json)['data'];
    if (rows is! List || rows.length > 500) throw const WeiboException(WeiboFailure.schema);
    final seen = <String>{};
    final result = <WeiboDirectoryCard>[];
    for (final row in rows) {
      final item = _object(row);
      final id = validateLiveId(_text(item['liveid']));
      if (!seen.add(id)) throw const WeiboException(WeiboFailure.identity);
      result.add(
        WeiboDirectoryCard(
          liveId: id,
          ownerId: _owner(item['uid']),
          nickname: _text(item['nickname']),
          cover: _image(item['cover']),
        ),
      );
    }
    return List.unmodifiable(result);
  }

  static WeiboLiveDetail parseDetail(
    Map<String, dynamic> json, {
    required String expectedLiveId,
    int? expectedOwnerId,
  }) {
    validateLiveId(expectedLiveId);
    if (expectedOwnerId != null) _owner(expectedOwnerId);
    final item = _success(json);
    final id = validateLiveId(_text(item['liveId']));
    final user = _object(item['user']);
    final owner = _owner(user['uid']);
    if (id != expectedLiveId || (expectedOwnerId != null && owner != expectedOwnerId)) {
      throw const WeiboException(WeiboFailure.identity);
    }
    final status = _number(item['status']);
    final limit = _number(item['watch_limit']);
    final paid = _binary(item['pay_live_status']);
    final enabled = _binary(item['play_switch']);
    // Normal account/session handling is a separate future contract. Do not expose
    // trial media merely because pay_live_status or a URL is present.
    final access = enabled == 0
        ? WeiboAccess.disabled
        : limit != 0
        ? WeiboAccess.restricted
        : WeiboAccess.public;
    final state = access != WeiboAccess.public
        ? WeiboBroadcastState.unknown
        : switch (status) {
            1 => WeiboBroadcastState.live,
            3 => WeiboBroadcastState.replay,
            _ => WeiboBroadcastState.unknown,
          };
    final urls = <String>{};
    if (state == WeiboBroadcastState.live) {
      for (final key in ['live_origin_flv_url', 'live_origin_hls_url']) {
        final text = _text(item[key]);
        if (text.isNotEmpty) urls.add(_url(text));
      }
    }
    return WeiboLiveDetail(
      liveId: id,
      ownerId: owner,
      title: _text(item['title']),
      nickname: _text(user['screenName']),
      cover: _image(item['cover']),
      avatar: _image(user['profileImageUrl']),
      access: access,
      state: state,
      reportedStatus: status,
      watchLimit: limit,
      payLiveStatus: paid,
      width: _number(item['width']),
      height: _number(item['height']),
      mediaUrls: List.unmodifiable(urls),
    );
  }
}

// 3.x's weibo_link.dart ---------------------------------------------------------

/// Broadcast watch URLs only. A profile UID is not a persistent live room.
class WeiboLink {
  static String? parse(String raw) {
    final value = raw.trim();
    if (RegExp(r'[\\\s]').hasMatch(value)) return null;
    if (_valid(value)) return value;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        !{'weibo.com', 'www.weibo.com'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    // Inspect the original path before Uri normalizes dot segments. Only the
    // identifier's colon may be escaped; no double decoding or encoded slashes.
    final authorityAndPath = value.substring(value.indexOf('://') + 3).split(RegExp(r'[?#]')).first;
    final slash = authorityAndPath.indexOf('/');
    if (slash < 0) return null;
    final match = RegExp(r'^/l/wblive/[pm]/show/([^/]+)/?$').firstMatch(authorityAndPath.substring(slash));
    if (match == null) return null;
    final id = match[1]!.replaceAll(RegExp('%3a', caseSensitive: false), ':');
    try {
      return WeiboApi.validateLiveId(id);
    } on WeiboException {
      return null;
    }
  }

  static bool _valid(String value) {
    try {
      WeiboApi.validateLiveId(value);
      return true;
    } on WeiboException {
      return false;
    }
  }

  static String url(String id) => 'https://weibo.com/l/wblive/p/show/${WeiboApi.validateLiveId(id)}';
}

// 3.x's weibo_site.dart ---------------------------------------------------------

class _WeiboChoice {
  const _WeiboChoice(this.liveId, this.ownerId);
  final String liveId;
  final int ownerId;
}

/// Public broadcast adapter. Registration and account-following are separate
/// contracts; fresh resolution never swaps to an unrelated/new broadcast.
class WeiboSite {
  WeiboSite({WeiboApi? api}) : _api = api ?? WeiboApi(request: _fixtureRequest);
  final WeiboApi _api;
  String get id => 'weibo';
  String get name => i18n('site_weibo');
  String get directoryNoticeKey => 'weibo_directory_scope';

  void _page(int page, [int pageSize = 30]) {
    if (page < 1 || pageSize < 1 || pageSize > 1000) throw const WeiboException(WeiboFailure.schema);
  }

  void _cancel(CancelToken? cancel) {
    if (cancel?.isCancelled == true) throw const WeiboException(WeiboFailure.cancelled);
  }

  String _id(String roomId, String platform) {
    if (platform != id) throw const WeiboException(WeiboFailure.identity);
    return WeiboApi.validateLiveId(roomId);
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    _cancel(cancel);
    _page(page);
    if (category != null &&
        (category.platform != id || category.areaType != 'recommendation' || category.areaId != 'live')) {
      throw const WeiboException(WeiboFailure.schema);
    }
    if (page > 1) return LiveDirectoryPage(page: page, hasMore: false, rooms: const []);
    final cards = await _api.directory(cancel: cancel);
    return LiveDirectoryPage(
      page: page,
      hasMore: false,
      rooms: cards.map(
        (card) => LiveRoom(
          platform: id,
          roomId: card.liveId,
          userId: '${card.ownerId}',
          nick: card.nickname,
          title: card.nickname,
          cover: card.cover,
          link: WeiboLink.url(card.liveId),
          liveStatus: LiveStatus.unknown,
          audienceMetricType: AudienceMetricType.unknown,
          watching: '',
          notice: i18n('weibo_room_scope'),
        ),
      ),
    );
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    _page(page, pageSize);
    return (await getDirectoryPage(page: page)).rooms;
  }

  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    _page(page, pageSize);
    return (await getDirectoryPage(page: page, category: category)).rooms;
  }

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    _page(page, pageSize);
    return page == 1
        ? [
            LiveCategory(
              id: id,
              name: name,
              children: [
                LiveArea(
                  platform: id,
                  areaType: 'recommendation',
                  areaId: 'live',
                  areaName: i18n('weibo_public_directory'),
                  typeName: name,
                ),
              ],
            ),
          ]
        : [];
  }

  LiveRoom _room(WeiboLiveDetail detail) => LiveRoom(
    platform: id,
    roomId: detail.liveId,
    userId: '${detail.ownerId}',
    title: detail.title,
    nick: detail.nickname,
    avatar: detail.avatar,
    cover: detail.cover,
    link: WeiboLink.url(detail.liveId),
    liveStatus: switch (detail.state) {
      WeiboBroadcastState.live => LiveStatus.live,
      WeiboBroadcastState.replay => LiveStatus.replay,
      WeiboBroadcastState.unknown => LiveStatus.unknown,
    },
    audienceMetricType: AudienceMetricType.unknown,
    watching: '',
    notice: [if (detail.access != WeiboAccess.public) i18n('weibo_restricted'), i18n('weibo_room_scope')].join('\n'),
    data: detail,
  );
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) async =>
      _room(await _api.detail(_id(roomId, platform)));
  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      getRoomDetail(roomId: roomId, platform: platform);
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      getRoomDetail(roomId: roomId, platform: platform);
  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId, platform: platform);
    if (room.liveStatus == LiveStatus.unknown) {
      final data = _detail(room);
      throw WeiboException(data.access == WeiboAccess.public ? WeiboFailure.unknownState : WeiboFailure.access);
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
    _cancel(cancel);
    _page(page, pageSize);
    if (page > 1) return [];
    final liveId = WeiboLink.parse(keyword);
    if (liveId != null) {
      try {
        return [_room(await _api.detail(liveId, cancel: cancel))];
      } on WeiboException catch (error) {
        if (error.kind == WeiboFailure.missing) return [];
        rethrow;
      }
    }
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return [];
    // Only filter the current official recommendation snapshot. This is not
    // a broadcaster or full-site search and does not establish live status.
    final directory = await getDirectoryPage(cancel: cancel);
    return directory.rooms.where((room) => (room.nick ?? '').toLowerCase().contains(query)).take(pageSize).toList();
  }

  WeiboLiveDetail _detail(LiveRoom room) {
    _id(room.roomId ?? '', room.platform ?? '');
    final detail = room.data;
    if (detail is! WeiboLiveDetail || detail.liveId != room.roomId || '${detail.ownerId}' != room.userId) {
      throw const WeiboException(WeiboFailure.identity);
    }
    return detail;
  }

  void _live(WeiboLiveDetail detail) {
    if (detail.access != WeiboAccess.public) throw const WeiboException(WeiboFailure.access);
    if (detail.state == WeiboBroadcastState.unknown) throw const WeiboException(WeiboFailure.unknownState);
    if (detail.state != WeiboBroadcastState.live) throw const WeiboException(WeiboFailure.notLive);
    if (detail.mediaUrls.isEmpty) throw const WeiboException(WeiboFailure.mediaUnavailable);
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    final data = _detail(detail);
    if (data.state == WeiboBroadcastState.replay) return [];
    _live(data);
    return List.unmodifiable([
      LivePlayQuality(
        id: 'original',
        quality: i18n('weibo_original_stream'),
        data: _WeiboChoice(data.liveId, data.ownerId),
      ),
    ]);
  }

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality) async {
    final data = _detail(detail);
    _live(data);
    final choice = quality.data;
    if (quality.selectionId != 'original' ||
        choice is! _WeiboChoice ||
        choice.liveId != data.liveId ||
        choice.ownerId != data.ownerId) {
      throw const WeiboException(WeiboFailure.identity);
    }
    // No observed URL expiry contract. Refresh at each new playback/recording
    // attempt instead of caching signed URLs or guessing a lifetime.
    final fresh = await _api.detail(data.liveId, expectedOwnerId: data.ownerId);
    _live(fresh);
    return LivePlayUrlResolution(urls: fresh.mediaUrls, appliedQualityData: 'original');
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) =>
      _resolve(detail, quality);
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality);
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await _resolve(detail, quality)).urls;
}
