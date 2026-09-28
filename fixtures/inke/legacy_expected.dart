// Writes expected.json for the Inke samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.14-inke.md, "样本与 v3 的冻结输出").
//
// The archive has no Inke expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below is 3.x's InkeApi
// and InkeSite, copied from legacy/lib/core/site/inke/inke_api.dart and
// inke_site.dart (archive/v4). 3.x already injected its transport
// (`InkeRequest`), so only that function is replaced: it answers from the
// samples by host, path and query, like the legacy FixtureAdapter, with the
// empty body 3.x read for any status other than 200, and throws a StateError
// for a request without a sample. `i18n` is replaced by the Chinese text of
// the keys used (`site_inke`, `inke_media_unavailable`); the danmaku getter
// is left out. Dio's CancelToken, 3.x's LiveRoom, LiveArea, LiveCategory,
// LivePlayQuality and LiveDirectoryPage are reduced to the parts these
// classes use (constructor defaults, the mutable fields, isLiveNow,
// isExplicitlyOfflineNow, selectionId, toJson). The response-body reader
// (`readBody`) is left out: it only ran on the network path.
// The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`).
//
// Run from the repository root: dart run fixtures/inke/legacy_expected.dart
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/inke';

/// Keywords run against the S01 showcases: shared by the top list and a
/// channel (糖果), several matches (西, 欧阳), letters in another case (mee),
/// many matches for paging (🎶) and none.
const _keywords = ['糖果', '西', '欧阳', 'mee', '🎶', 'zxqvnoresultfixture'];

void main() async {
  await _top();
  await _channels('S01-channels');
  await _directoryOnly('S05-unlisted-top');
  await _channels('S05-unlisted-channels');
  await _showcaseMedia();
  await _detail('S03-share-live', '771067357', showcases: ['S01-top']);
  await _detail('S03-share-offline', '1');
  await _detail(
    'S05-unlisted-share',
    '778920027',
    showcases: ['S05-unlisted-top', 'S05-unlisted-hot', 'S05-unlisted-channels'],
  );
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final List<Uri> _requests = [];

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _replay(List<String> samples) {
  _samples = [for (final sample in samples) _meta(sample)];
  _requests.clear();
}

bool _sameQuery(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

/// 3.x's `InkeRequest` over the samples: 3.x read no body for a status
/// other than 200.
Future<({int status, String body})> _fixtureRequest(Uri uri, CancelToken? cancel) async {
  _requests.add(uri);
  for (final meta in _samples) {
    final recorded = Uri.parse((meta['request'] as Map)['url'] as String);
    if (recorded.host == uri.host && recorded.path == uri.path && _sameQuery(recorded.queryParameters, uri.queryParameters)) {
      final status = (meta['response'] as Map)['status'] as int;
      if (status != 200) return (status: status, body: '');
      return (status: 200, body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync());
    }
  }
  throw StateError('No recorded sample for GET $uri');
}

InkeSite _site() => InkeSite(api: InkeApi(request: _fixtureRequest));

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

// Samples ---------------------------------------------------------------------

/// `Live_top_pc`: the recommendations (native page and 3.x's slices) and
/// the keyword search over it and [channels].
Future<void> _top() async {
  _replay(['S01-top', 'S01-channels']);
  final site = _site();
  final value = <String, Object?>{
    'getDirectoryPage': await _traced(() => site.getDirectoryPage(), _page),
    'getDirectoryPage(page: 2)': await _traced(() => site.getDirectoryPage(page: 2), _page),
    'getRecommendRooms': {
      for (final (page, size) in [(1, 30), (1, 3), (2, 3), (3, 3), (4, 3)])
        'page $page, pageSize $size': await _traced(() => site.getRecommendRooms(page: page, pageSize: size), _rooms),
    },
    'searchRooms': {
      for (final keyword in _keywords)
        keyword: await _traced(() => site.searchRooms(keyword, pageSize: 20), _rooms),
      for (final page in [1, 2, 3])
        '🎶 page $page, pageSize 3': await _traced(() => site.searchRooms('🎶', page: page, pageSize: 3), _rooms),
    },
    'supportsSearchPaginationFor': {for (final keyword in _keywords) keyword: site.supportsSearchPaginationFor(keyword)},
  };
  _write(
    'S01-top',
    'InkeSite.getDirectoryPage + getRecommendRooms; searchRooms + supportsSearchPaginationFor (with S01-channels)',
    value,
  );
}

/// `Live_top_pc` alone: the native page.
Future<void> _directoryOnly(String sample) async {
  _replay([sample]);
  final site = _site();
  _write(sample, 'InkeSite.getDirectoryPage', {'getDirectoryPage': await _traced(() => site.getDirectoryPage(), _page)});
}

/// `Live_channel_pc`: the catalog and every channel's page; the first
/// channel also as 3.x's slices.
Future<void> _channels(String sample) async {
  _replay([sample]);
  final site = _site();
  final categories = await site.getCategores(1, 30);
  final areas = categories.single.children;
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
    'getDirectoryPage': {
      for (final area in areas) area.areaId!: await _traced(() => site.getDirectoryPage(category: area), _page),
    },
    'getCategoryRooms': {
      for (final (page, size) in [(1, 30), (1, 3), (2, 3), (3, 3), (4, 3)])
        'page $page, pageSize $size': await _traced(
          () => site.getCategoryRooms(areas.first, page: page, pageSize: size),
          _rooms,
        ),
    },
  };
  _write(sample, 'InkeSite.getCategores + getDirectoryPage + getCategoryRooms (the first channel)', value);
}

/// The pull URLs 3.x's media lookup (`InkeApi._showcaseMedia`: the top
/// list, then the hot lists, then the channels) finds for every showcase row
/// of the S05 snapshot, by `uid` and `live_id`.
Future<void> _showcaseMedia() async {
  const samples = ['S05-unlisted-top', 'S05-unlisted-hot', 'S05-unlisted-channels'];
  _replay(samples);
  final api = InkeApi(request: _fixtureRequest);
  final rows = <Map<String, dynamic>>[];
  for (final sample in samples) {
    final data = (jsonDecode(File('$_root/$sample/body.json').readAsStringSync()) as Map)['data'] as Map;
    final list = data['list'];
    if (sample.endsWith('top')) rows.addAll((list as List).cast());
    if (sample.endsWith('hot')) {
      for (final group in (list as Map).values) {
        rows.addAll((group as List).cast());
      }
    }
    if (sample.endsWith('channels')) {
      for (final group in (list as List)) {
        rows.addAll(((group as Map)['list'] as List).cast());
      }
    }
  }
  final value = <String, Object?>{};
  for (final row in rows) {
    final key = '${row['uid']}/${row['live_id']}';
    if (value.containsKey(key)) continue;
    value[key] = await _traced(() => api._showcaseMedia('${row['uid']}', '${row['live_id']}'), (urls) => urls);
  }
  _write('S05-unlisted-hot', 'InkeApi._showcaseMedia per showcase row (with S05-unlisted-top, -channels)', value);
}

Future<void> _detail(String sample, String uid, {List<String> showcases = const []}) async {
  _replay([sample, ...showcases]);
  final site = _site();
  final link = 'https://www.inke.cn/liveroom/index.html?uid=$uid&id=1';
  final value = <String, Object?>{
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: uid, platform: 'inke'), _roomProjection),
    'getRoomDetailForRefresh': await _traced(
      () => site.getRoomDetailForRefresh(roomId: uid, platform: 'inke'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _traced(
      () => site.getRoomDetailForRecording(roomId: uid, platform: 'inke'),
      _roomProjection,
    ),
    'searchRooms': await _traced(() => site.searchRooms(uid), _rooms),
    'searchRooms(link)': await _traced(() => site.searchRooms(link), _rooms),
    'supportsSearchPaginationFor': site.supportsSearchPaginationFor(uid),
    'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: uid, platform: 'inke'), (live) => live),
  };
  try {
    final detail = await site.getRoomDetail(roomId: uid, platform: 'inke');
    value['externalRoomUrl'] = InkeSite.externalRoomUrl(detail);
    final qualities = await site.getPlayQualites(detail: detail);
    value['getPlayQualites'] = [
      for (final quality in qualities)
        {
          'quality': quality.quality,
          'id': quality.id,
          'sort': quality.sort,
          'getPlayUrls': await site.getPlayUrls(detail: detail, quality: quality),
        },
    ];
    final flv = LivePlayQuality(id: 'flv', quality: 'FLV');
    value['getPlayUrls(flv)'] = await _outcome(() => site.getPlayUrls(detail: detail, quality: flv), (urls) => urls);
    value['resolvePlayUrlsForRecoveryRaw'] = await _traced(
      () => site.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: flv),
      (resolution) => {'urls': resolution.urls, 'appliedQualityData': resolution.appliedQualityData},
    );
  } on Object catch (error) {
    value['getPlayQualites'] = _errorProjection(error);
  }
  _write(
    sample,
    'InkeSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + searchRooms + getLiveStatus + '
        'externalRoomUrl + getPlayQualites + getPlayUrls + resolvePlayUrlsForRecoveryRaw'
        '${showcases.isEmpty ? '' : ' (with ${showcases.join(', ')})'}',
    value,
  );
}

// 3.x models (the parts the Inke classes use) ----------------------------------

class CancelToken {
  bool isCancelled = false;
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

// 3.x's inke_api.dart -----------------------------------------------------------

enum InkeFailure { transport, access, rateLimited, service, notFound, schema, cancelled, mediaUnavailable }

class InkeException implements Exception {
  const InkeException(this.kind, {this.message});
  final InkeFailure kind;
  final String? message;
  @override
  String toString() => message ?? 'Inke ${kind.name}';
}

typedef InkeRequest = Future<({int status, String body})> Function(Uri uri, CancelToken? cancel);

class _NoCurrentBroadcast implements Exception {
  const _NoCurrentBroadcast();
}

class InkeApi {
  InkeApi({required InkeRequest request}) : _request = request;
  static const origin = 'https://www.inke.cn';
  static const apiOrigin = 'https://webapi.busi.inke.cn';
  static const responseLimit = 1024 * 1024;
  static const playHeaders = {'Referer': '$origin/', 'Origin': origin, 'User-Agent': 'Mozilla/5.0'};
  final InkeRequest _request;

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query, CancelToken? cancel}) async {
    if (cancel?.isCancelled == true) throw const InkeException(InkeFailure.cancelled);
    late final ({int status, String body}) response;
    try {
      response = await _request(Uri.parse('$apiOrigin/web/$path').replace(queryParameters: query), cancel);
    } catch (error) {
      if (cancel?.isCancelled == true) throw const InkeException(InkeFailure.cancelled);
      if (error is InkeException) rethrow;
      // The harness has no network: a request without a sample is a harness
      // error, not 3.x's transport failure.
      if (error is StateError) rethrow;
      throw const InkeException(InkeFailure.transport);
    }
    if (cancel?.isCancelled == true) throw const InkeException(InkeFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      401 || 403 => InkeFailure.access,
      404 => InkeFailure.notFound,
      429 => InkeFailure.rateLimited,
      >= 500 => InkeFailure.service,
      _ => InkeFailure.transport,
    };
    if (failure != null) throw InkeException(failure);
    if (response.body.length > responseLimit || utf8.encode(response.body).length > responseLimit) {
      throw const InkeException(InkeFailure.schema);
    }
    try {
      final envelope = _object(jsonDecode(response.body));
      final code = _integer(envelope['error_code']);
      if (code == null) throw const InkeException(InkeFailure.schema);
      // Only the room endpoint's observed no-current-broadcast code is offline.
      // Unknown service codes, missing streams and HTTP errors are not offline.
      if (code == 1099999920 && path == 'live_share_pc') throw const _NoCurrentBroadcast();
      if (code != 0) throw const InkeException(InkeFailure.service);
      return _object(envelope['data']);
    } on FormatException {
      throw const InkeException(InkeFailure.schema);
    }
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) throw const InkeException(InkeFailure.schema);
    return Map<String, dynamic>.from(value);
  }

  static String _text(Object? value) => value is String ? value.trim() : '';
  static int? _integer(Object? value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  static String _id(Object? value) => roomId(value is int ? '$value' : _text(value));
  static String roomId(String input) {
    final value = input.trim();
    if (!RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(value)) throw const InkeException(InkeFailure.schema);
    return value;
  }

  static String? roomFromUri(Uri uri) {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        !{'inke.cn', 'www.inke.cn', 'inke.com', 'www.inke.com'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) ||
        uri.path != '/liveroom/index.html') {
      return null;
    }
    try {
      final values = uri.queryParametersAll['uid'];
      return values?.length == 1 ? roomId(values!.single) : null;
    } on FormatException {
      return null;
    } on InkeException {
      return null;
    }
  }

  static String _picture(Object? value) {
    final text = _text(value);
    final uri = Uri.tryParse(text);
    return uri != null && {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty && uri.userInfo.isEmpty
        ? text
        : '';
  }

  /// Keep the exact signed query. No HLS URL synthesis, encryption rewriting or
  /// inference that a different broadcast belonging to the same UID is current.
  static String? plainFlv(Object? value, {required String broadcastId}) {
    final text = _text(value);
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) ||
        uri.host != 'live-pull-ws.ikstatic.cn' ||
        uri.fragment.isNotEmpty ||
        uri.path != '/live/${roomId(broadcastId)}_t.flv') {
      return null;
    }
    return text;
  }

  static List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List || value.length > 1000) throw const InkeException(InkeFailure.schema);
    return value.map(_object).toList();
  }

  static LiveRoom _card(Map<String, dynamic> row) {
    final uid = _id(row['uid']);
    final broadcastId = _id(row['live_id']);
    final nick = _text(row['nick']);
    if (nick.isEmpty) throw const InkeException(InkeFailure.schema);
    return LiveRoom(
      platform: 'inke',
      roomId: uid,
      userId: uid,
      nick: nick,
      title: nick,
      avatar: _picture(row['portrait']),
      cover: _picture(row['portrait']),
      link: '$origin/liveroom/index.html?uid=$uid&id=$broadcastId',
      status: true,
      liveStatus: LiveStatus.live,
      isRecord: false,
      watching: '',
      audienceMetricType: AudienceMetricType.unknown,
    );
  }

  Future<List<Map<String, dynamic>>> _channels({CancelToken? cancel}) async {
    final data = await _get('Live_channel_pc', cancel: cancel);
    final groups = _rows(data['list']);
    if (groups.length > 100) throw const InkeException(InkeFailure.schema);
    final keys = <String>{};
    for (final group in groups) {
      final key = _text(group['tab_key']);
      if (!RegExp(r'^[a-zA-Z0-9]{1,64}$').hasMatch(key) || !keys.add(key) || _text(group['channel_name']).isEmpty) {
        throw const InkeException(InkeFailure.schema);
      }
      _rows(group['list']);
    }
    return groups;
  }

  Future<List<LiveArea>> categories({CancelToken? cancel}) async => [
    for (final group in await _channels(cancel: cancel))
      LiveArea(
        platform: 'inke',
        areaType: 'showcase',
        areaId: _text(group['tab_key']),
        areaName: _text(group['channel_name']),
        typeName: '映客官网精选',
      ),
  ];

  /// Filter the two finite public website showcases locally. This is not a
  /// server-side nickname index and cannot discover channels outside them.
  Future<List<LiveRoom>> searchShowcases(String keyword, {int page = 1, int pageSize = 20, CancelToken? cancel}) async {
    final query = keyword.trim().toLowerCase();
    if (page < 1 || page > 10000 || pageSize < 1 || pageSize > 60 || query.length > 100) {
      throw const InkeException(InkeFailure.schema);
    }
    if (query.isEmpty) return const [];
    final top = _rows((await _get('Live_top_pc', cancel: cancel))['list']);
    final groups = await _channels(cancel: cancel);
    final matches = <String, LiveRoom>{};
    for (final row in [...top, for (final group in groups) ..._rows(group['list'])]) {
      final room = _card(row);
      if (room.nick!.toLowerCase().contains(query)) matches.putIfAbsent(room.roomId!, () => room);
    }
    final start = (page - 1) * pageSize;
    if (start >= matches.length) return const [];
    return List.unmodifiable(matches.values.skip(start).take(pageSize));
  }

  Future<LiveDirectoryPage> directoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1 || (category != null && (category.platform != 'inke' || category.areaType != 'showcase'))) {
      throw const InkeException(InkeFailure.schema);
    }
    if (cancel?.isCancelled == true) throw const InkeException(InkeFailure.cancelled);
    // One finite website showcase; do not invent an offset API from its size.
    if (page > 1) return LiveDirectoryPage(rooms: [], page: page, hasMore: false);
    late final List<Map<String, dynamic>> rows;
    if (category == null) {
      rows = _rows((await _get('Live_top_pc', cancel: cancel))['list']);
    } else {
      final matches = (await _channels(cancel: cancel)).where((group) => group['tab_key'] == category.areaId).toList();
      if (matches.length != 1) throw const InkeException(InkeFailure.notFound);
      rows = _rows(matches.single['list']);
    }
    final rooms = <String, LiveRoom>{};
    for (final row in rows) {
      final card = _card(row);
      rooms.putIfAbsent(card.roomId!, () => card);
    }
    return LiveDirectoryPage(rooms: rooms.values, page: page, hasMore: false);
  }

  Future<List<String>> _showcaseMedia(String uid, String broadcastId, {CancelToken? cancel}) async {
    for (final path in ['Live_top_pc', 'Live_hot_pc', 'Live_channel_pc']) {
      final data = await _get(path, cancel: cancel);
      final groups = switch (path) {
        'Live_hot_pc' => _object(data['list']).values.toList(),
        'Live_channel_pc' => _rows(data['list']).map((group) => group['list']).toList(),
        _ => [data['list']],
      };
      if (groups.length > 100) throw const InkeException(InkeFailure.schema);
      final urls = <String>{};
      for (final group in groups) {
        for (final row in _rows(group)) {
          if (_id(row['uid']) != uid || _id(row['live_id']) != broadcastId) continue;
          final url = plainFlv(row['stream_addr'], broadcastId: broadcastId);
          if (url != null) urls.add(url);
        }
      }
      if (urls.isNotEmpty) return List.unmodifiable(urls);
    }
    // This means the current anonymous website catalogue has no verified media
    // for the broadcast; it does not mean that the broadcaster went offline.
    throw const InkeException(InkeFailure.mediaUnavailable);
  }

  Future<LiveRoom> detail(String input, {bool playback = true, CancelToken? cancel}) async {
    final uid = roomId(input);
    late final Map<String, dynamic> info;
    try {
      info = await _get('live_share_pc', query: {'uid': uid}, cancel: cancel);
    } on _NoCurrentBroadcast {
      return LiveRoom(
        platform: 'inke',
        roomId: uid,
        userId: uid,
        link: '$origin/liveroom/index.html?uid=$uid',
        status: false,
        liveStatus: LiveStatus.offline,
        isRecord: false,
      );
    }
    if (_id(info['live_uid']) != uid || !{1, '1', true}.contains(info['status'])) {
      throw const InkeException(InkeFailure.schema);
    }
    final broadcastId = _id(info['liveid']);
    final owner = _object(info['media_info']);
    if (_id(owner['inke_id']) != uid || _text(owner['nick']).isEmpty) throw const InkeException(InkeFailure.schema);
    final urls = playback ? await _showcaseMedia(uid, broadcastId, cancel: cancel) : <String>[];
    return LiveRoom(
      platform: 'inke',
      roomId: uid,
      userId: uid,
      nick: _text(owner['nick']),
      title: _text(info['live_name']).isEmpty ? _text(owner['nick']) : _text(info['live_name']),
      avatar: _picture(owner['portrait']),
      cover: _picture(info['portrait']),
      link: '$origin/liveroom/index.html?uid=$uid&id=$broadcastId',
      status: true,
      liveStatus: LiveStatus.live,
      isRecord: false,
      watching: '',
      audienceMetricType: AudienceMetricType.unknown,
      data: playback ? [LivePlayQuality(id: 'flv', quality: 'FLV', data: urls)] : null,
    );
  }
}

// 3.x's inke_site.dart ------------------------------------------------------------

class InkeSite {
  InkeSite({InkeApi? api}) : _api = api ?? InkeApi(request: _fixtureRequest);
  final InkeApi _api;

  /// Official room pages need both the durable UID and a broadcast ID. Older
  /// favorites/offline metadata can lack the latter; do not invent a room URL.
  static String externalRoomUrl(LiveRoom room) {
    final uri = Uri.tryParse(room.link?.trim() ?? '');
    if (uri != null && room.platform == 'inke' && room.roomId != null && InkeApi.roomFromUri(uri) == room.roomId) {
      try {
        final ids = uri.queryParametersAll['id'];
        if (ids?.length == 1 && RegExp(r'^[0-9]{1,32}$').hasMatch(ids!.single)) return uri.toString();
      } on FormatException {
        // Malformed imported links use the official homepage.
      }
    }
    return '${InkeApi.origin}/';
  }

  String get id => 'inke';
  String get name => '映客';
  String get directoryNoticeKey => 'inke_directory_scope';
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) =>
      _api.directoryPage(page: page, category: category, cancel: cancel);
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async =>
      page == 1 ? [LiveCategory(id: id, name: name, children: await _api.categories())] : [];

  Future<List<LiveRoom>> _slice({required int page, required int pageSize, LiveArea? category}) async {
    if (page < 1 || pageSize < 1) throw const InkeException(InkeFailure.schema);
    // Legacy list consumers slice one complete website showcase. The main
    // popular/category routes use the native contract and keep overflow once.
    final rows = (await getDirectoryPage(category: category)).rooms;
    if (page - 1 > rows.length ~/ pageSize) return [];
    final start = (page - 1) * pageSize;
    if (start < 0 || start >= rows.length) return [];
    return rows.sublist(start, (start + pageSize).clamp(start, rows.length));
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) => _slice(page: page, pageSize: pageSize);
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) =>
      _slice(page: page, pageSize: pageSize, category: category);

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  static String? _searchUid(String input) {
    try {
      return InkeApi.roomId(input);
    } on InkeException {
      final uri = Uri.tryParse(input);
      return uri == null ? null : InkeApi.roomFromUri(uri);
    }
  }

  bool supportsSearchPaginationFor(String keyword) {
    final input = keyword.trim();
    return input.isNotEmpty && _searchUid(input) == null && Uri.tryParse(input)?.hasScheme != true;
  }

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page < 1 || pageSize < 1) throw const InkeException(InkeFailure.schema);
    final input = keyword.trim();
    final uid = _searchUid(input);
    if (uid == null) {
      // A malformed/shared URL is not a nickname query.
      if (Uri.tryParse(input)?.hasScheme == true) return const [];
      return _api.searchShowcases(input, page: page, pageSize: pageSize, cancel: cancel);
    }
    if (page != 1) return const [];
    try {
      final room = await _api.detail(uid, playback: false, cancel: cancel);
      if (room.isExplicitlyOfflineNow) {
        // The public no-current-broadcast response has no profile metadata.
        // Keep the search card identifiable without inventing a nickname.
        room.title = 'UID $uid';
        room.nick = 'UID $uid';
      }
      return [room];
    } on InkeException catch (error) {
      if (error.kind == InkeFailure.notFound) return const [];
      rethrow;
    }
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool playback}) async {
    if (platform != id) throw const InkeException(InkeFailure.schema);
    try {
      return await _api.detail(roomId, playback: playback);
    } on InkeException catch (error) {
      if (error.kind == InkeFailure.mediaUnavailable) {
        throw InkeException(error.kind, message: '该房间仍在直播，但当前官网精选未提供已验证的公开播放地址，请稍后刷新。');
      }
      rethrow;
    }
  }

  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) =>
      _detail(roomId, platform, playback: true);
  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      _detail(roomId, platform, playback: true);
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      _detail(roomId, platform, playback: false);
  Future<bool> getLiveStatus({required String platform, required String roomId}) async =>
      (await getRoomDetailForRefresh(roomId: roomId, platform: platform)).isLiveNow;
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.platform != id) throw const InkeException(InkeFailure.schema);
    if (detail.isExplicitlyOfflineNow) return [];
    if (!detail.isLiveNow || detail.data is! List<LivePlayQuality> || (detail.data as List).isEmpty) {
      throw const InkeException(InkeFailure.schema);
    }
    return List.unmodifiable(detail.data as List<LivePlayQuality>);
  }

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    for (final current in await getPlayQualites(detail: detail)) {
      if (current.selectionId == quality.selectionId) return List.unmodifiable(current.data as List<String>);
    }
    throw const InkeException(InkeFailure.mediaUnavailable);
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final fresh = await getRoomDetail(roomId: detail.roomId ?? '', platform: detail.platform ?? '');
    return LivePlayUrlResolution(
      urls: await getPlayUrls(detail: fresh, quality: quality),
      appliedQualityData: quality.selectionId,
    );
  }
}
