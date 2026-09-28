// Writes expected.json for the Missevan samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.13-missevan.md, "样本与 v3 的冻结输出").
//
// The archive has no Missevan expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below is 3.x's
// MissevanApi and MissevanSite, copied from
// legacy/lib/core/site/missevan/missevan_api.dart and missevan_site.dart
// (archive/v4). 3.x already injected its transport (`MissevanRequest`), so
// only that function is replaced: it answers from the samples by host, path
// and query, like the legacy FixtureAdapter, with the empty body 3.x read for
// any status other than 200, and throws a StateError for a request without
// a sample. Dio's CancelToken, 3.x's LiveRoom, LiveArea, LiveCategory,
// LivePlayQuality and LiveDirectoryPage are reduced to the parts these
// classes use (constructor defaults, the mutable fields, isLiveNow,
// isExplicitlyOfflineNow, selectionId, toJson). The response-body reader
// (`readBody`) is left out: it only ran on the network path.
// The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`).
//
// Run from the repository root: dart run fixtures/missevan/legacy_expected.dart
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/missevan';

void main() async {
  await _catalog();
  for (final (sample, page) in [('S02-list-p1', 1), ('S02-list-last', 29), ('S02-list-beyond', 30)]) {
    await _directory(sample, page: page);
  }
  await _directory(
    'S02-list-catalog',
    area: LiveArea(platform: 'missevan', areaType: 'catalog', areaId: '104', areaName: '音乐', typeName: '猫耳 FM'),
  );
  await _directory(
    'S02-list-tag',
    area: LiveArea(platform: 'missevan', areaType: 'tag', areaId: '1', areaName: '新星', typeName: '猫耳 FM'),
  );
  // 3.x has no 团播 area (its catalog failed on the tab); asked anyway, it
  // refuses the namespace before any request.
  await _directory(
    'S02-list-team',
    area: LiveArea(platform: 'missevan', areaType: 'list', areaId: '4', areaName: '团播', typeName: '猫耳 FM'),
  );
  for (final sample in ['S03-search', 'S03-search-p2', 'S03-search-empty']) {
    await _search(sample);
  }
  await _detail('S04-live', '453091860');
  await _detail('S04-offline', '507069668');
  await _detail('S04-notfound', '1');
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

/// 3.x's `MissevanRequest` over the samples: 3.x read no body for a status
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

MissevanSite _site() => MissevanSite(api: MissevanApi(request: _fixtureRequest));

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

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere((key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty));
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

// Samples ---------------------------------------------------------------------

Future<void> _catalog() async {
  _replay(['S01-meta']);
  final site = _site();
  Object? project(List<LiveCategory> categories) => [
    for (final category in categories)
      {
        'id': category.id,
        'name': category.name,
        'children': [for (final area in category.children) area.toJson()],
      },
  ];
  final value = <String, Object?>{'getCategores': await _outcome(() => site.getCategores(1, 30), project)};
  // What 3.x made of the tabs it knew: the recorded answer without the tab
  // types it refused (the `list` tab 团播, added by the site after 3.x).
  final body = jsonDecode(File('$_root/S01-meta/body.json').readAsStringSync()) as Map<String, dynamic>;
  final info = body['info'] as Map<String, dynamic>;
  info['tabs'] = [
    for (final tab in info['tabs'] as List)
      if ({'catalog', 'tag'}.contains((tab as Map)['type'])) tab,
  ];
  final known = MissevanSite(
    api: MissevanApi(request: (uri, _) async => (status: 200, body: jsonEncode(body))),
  );
  value['getCategoresWithoutListTab'] = await _outcome(() => known.getCategores(1, 30), project);
  _write(
    'S01-meta',
    'MissevanSite.getCategores (getCategoresWithoutListTab: the same answer without the list tab)',
    value,
  );
}

Future<void> _directory(String sample, {int page = 1, LiveArea? area}) async {
  _replay([sample]);
  final site = _site();
  final value = <String, Object?>{
    'getDirectoryPage': await _outcome(
      () => site.getDirectoryPage(page: page, category: area),
      (result) => {'rooms': _rooms(result.rooms), 'page': result.page, 'hasMore': result.hasMore},
    ),
    'requests': [for (final uri in _requests) uri.toString()],
  };
  _write(sample, 'MissevanSite.getDirectoryPage', value);
}

Future<void> _search(String sample) async {
  _replay([sample]);
  final query = Uri.parse((_meta(sample)['request'] as Map)['url'] as String).queryParameters;
  final keyword = query['s']!;
  final page = int.parse(query['p']!);
  final size = int.parse(query['page_size']!);
  final site = _site();
  _write(sample, 'MissevanSite.searchRooms + supportsSearchPaginationFor', {
    'searchRooms': await _outcome(() => site.searchRooms(keyword, page: page, pageSize: size), _rooms),
    'supportsSearchPaginationFor': site.supportsSearchPaginationFor(keyword),
  });
}

Future<void> _detail(String sample, String roomId) async {
  _replay([sample]);
  final site = _site();
  final value = <String, Object?>{
    'getRoomDetail': await _outcome(() => site.getRoomDetail(roomId: roomId, platform: 'missevan'), _roomProjection),
    'getRoomDetailForRefresh': await _outcome(
      () => site.getRoomDetailForRefresh(roomId: roomId, platform: 'missevan'),
      _roomProjection,
    ),
    'searchRooms': await _outcome(() => site.searchRooms(roomId), _rooms),
    'supportsSearchPaginationFor': site.supportsSearchPaginationFor(roomId),
    'getLiveStatus': await _outcome(() => site.getLiveStatus(roomId: roomId, platform: 'missevan'), (live) => live),
  };
  try {
    final detail = await site.getRoomDetail(roomId: roomId, platform: 'missevan');
    final qualities = await site.getPlayQualites(detail: detail);
    value['getPlayQualites'] = [
      for (final quality in qualities)
        {
          'quality': quality.quality,
          'id': quality.id,
          'sort': quality.sort,
          'getPlayUrls': [
            for (final url in await site.getPlayUrls(detail: detail, quality: quality))
              {
                'url': url,
                'getPlayUrlRefreshAt': site.getPlayUrlRefreshAt(url)?.toIso8601String(),
                'getPlayUrlInvalidAt': site.getPlayUrlInvalidAt(url)?.toIso8601String(),
              },
          ],
        },
    ];
  } on Object catch (error) {
    value['getPlayQualites'] = _errorProjection(error);
  }
  _write(
    sample,
    'MissevanSite.getRoomDetail + getRoomDetailForRefresh + searchRooms + getLiveStatus + getPlayQualites + '
        'getPlayUrls + getPlayUrlRefreshAt + getPlayUrlInvalidAt',
    value,
  );
}

// 3.x models (the parts the Missevan classes use) ------------------------------

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
  LiveDirectoryPage({required this.rooms, required this.page, required this.hasMore});

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

// 3.x's missevan_api.dart -------------------------------------------------------

enum MissevanFailure { transport, access, rateLimited, service, notFound, schema, cancelled, qualityUnavailable }

class MissevanException implements Exception {
  const MissevanException(this.kind);
  final MissevanFailure kind;
  @override
  String toString() => 'Missevan ${kind.name}';
}

typedef MissevanRequest = Future<({int status, String body})> Function(Uri uri, CancelToken? cancel);

class MissevanApi {
  MissevanApi({required MissevanRequest request}) : _request = request;
  static const origin = 'https://fm.missevan.com';
  static const responseLimit = 1024 * 1024;
  static const serverPageSize = 20;
  static const playHeaders = <String, String>{'Referer': '$origin/', 'Origin': origin, 'User-Agent': 'Mozilla/5.0'};
  final MissevanRequest _request;

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? query, CancelToken? cancel}) async {
    if (cancel?.isCancelled == true) throw const MissevanException(MissevanFailure.cancelled);
    late final ({int status, String body}) response;
    try {
      response = await _request(Uri.parse('$origin/api/v2/$path').replace(queryParameters: query), cancel);
    } catch (error) {
      if (cancel?.isCancelled == true) throw const MissevanException(MissevanFailure.cancelled);
      if (error is MissevanException) rethrow;
      // The harness has no network: a request without a sample is a harness
      // error, not 3.x's transport failure.
      if (error is StateError) rethrow;
      throw const MissevanException(MissevanFailure.transport);
    }
    if (cancel?.isCancelled == true) throw const MissevanException(MissevanFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      401 || 403 => MissevanFailure.access,
      404 => MissevanFailure.notFound,
      429 => MissevanFailure.rateLimited,
      >= 500 => MissevanFailure.service,
      _ => MissevanFailure.transport,
    };
    if (failure != null) throw MissevanException(failure);
    if (response.body.length > responseLimit || utf8.encode(response.body).length > responseLimit) {
      throw const MissevanException(MissevanFailure.schema);
    }
    late final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const MissevanException(MissevanFailure.schema);
    }
    final data = _object(decoded);
    final code = _integer(data['code']);
    if (code == null) throw const MissevanException(MissevanFailure.schema);
    if (code == 500030004) throw const MissevanException(MissevanFailure.notFound);
    if (code != 0) throw const MissevanException(MissevanFailure.service);
    return _object(data['info']);
  }

  static Map<String, dynamic> _object(Object? raw) {
    if (raw is! Map || raw.keys.any((key) => key is! String)) throw const MissevanException(MissevanFailure.schema);
    return Map<String, dynamic>.from(raw);
  }

  static String _text(Object? raw) => raw is String ? raw.trim() : '';
  static int? _integer(Object? raw) => raw is int ? raw : (raw is String ? int.tryParse(raw) : null);
  static String roomId(String input) {
    final id = input.trim();
    if (!RegExp(r'^[1-9][0-9]{0,17}$').hasMatch(id)) throw const MissevanException(MissevanFailure.schema);
    return id;
  }

  static String? roomFromUri(Uri uri) {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host != 'fm.missevan.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    try {
      final parts = uri.pathSegments.toList();
      if (parts.isNotEmpty && parts.last.isEmpty) parts.removeLast();
      return parts.length == 2 && parts.first == 'live' ? roomId(parts.last) : null;
    } on FormatException {
      return null;
    } on MissevanException {
      return null;
    }
  }

  static String _picture(Object? raw) {
    var value = _text(raw);
    if (value.startsWith('//')) value = 'https:$value';
    final uri = Uri.tryParse(value);
    return uri != null && {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty && uri.userInfo.isEmpty
        ? value
        : '';
  }

  Future<List<LiveArea>> categories({CancelToken? cancel}) async {
    final info = await _get('meta/data', cancel: cancel);
    final tabs = info['tabs'];
    if (tabs is! List || tabs.isEmpty || tabs.length > 100) throw const MissevanException(MissevanFailure.schema);
    final result = <String, LiveArea>{};
    for (final raw in tabs) {
      final tab = _object(raw);
      final type = _text(tab['type']);
      final id = _integer(tab['${type}_id']);
      final name = _text(tab['name']);
      if (!{'catalog', 'tag'}.contains(type) || id == null || id <= 0 || name.isEmpty) {
        throw const MissevanException(MissevanFailure.schema);
      }
      final key = '$type:$id';
      if (result.containsKey(key)) throw const MissevanException(MissevanFailure.schema);
      result[key] = LiveArea(
        platform: 'missevan',
        areaType: type,
        areaId: '$id',
        areaName: name,
        typeName: '猫耳 FM',
        areaPic: _picture(tab['icon_url']),
      );
    }
    return List.unmodifiable(result.values);
  }

  Future<List<LiveRoom>> directory({int page = 1, int pageSize = 30, LiveArea? category, CancelToken? cancel}) async {
    if (pageSize < 1 || pageSize > 100) throw const MissevanException(MissevanFailure.schema);
    return (await directoryPage(page: page, category: category, cancel: cancel)).rooms;
  }

  Future<MissevanDirectoryPage> directoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1 || page > 10000) throw const MissevanException(MissevanFailure.schema);
    final query = <String, String>{'p': '$page'};
    if (category != null) {
      if (category.platform != 'missevan' || !{'catalog', 'tag'}.contains(category.areaType)) {
        throw const MissevanException(MissevanFailure.schema);
      }
      query['${category.areaType}_id'] = roomId(category.areaId ?? '');
    }
    final info = await _get('chatroom/open/list', query: query, cancel: cancel);
    final pagination = _object(info['pagination']);
    final maxPage = _integer(pagination['maxpage']);
    final count = _integer(pagination['count']);
    final rows = info['Datas'];
    if (_integer(pagination['p']) != page ||
        _integer(pagination['pagesize']) != serverPageSize ||
        maxPage == null ||
        maxPage < 0 ||
        count == null ||
        count < 0 ||
        rows is! List ||
        rows.length > 100) {
      throw const MissevanException(MissevanFailure.schema);
    }
    if (page > maxPage && rows.isNotEmpty) throw const MissevanException(MissevanFailure.schema);
    final result = <String, LiveRoom>{};
    for (final raw in rows) {
      final room = _room(_object(raw));
      if (room.isLiveNow) result.putIfAbsent(room.roomId!, () => room);
    }
    return MissevanDirectoryPage(rooms: List.unmodifiable(result.values), page: page, maxPage: maxPage, count: count);
  }

  Future<List<LiveRoom>> searchPage(
    String keyword, {
    int page = 1,
    int pageSize = serverPageSize,
    CancelToken? cancel,
  }) async {
    final term = keyword.trim();
    if (term.isEmpty ||
        term.length > 100 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(term) ||
        page < 1 ||
        page > 10000 ||
        pageSize < 1 ||
        pageSize > 100) {
      throw const MissevanException(MissevanFailure.schema);
    }
    final info = await _get(
      'chatroom/search',
      query: {'s': term, 'p': '$page', 'page_size': '$pageSize'},
      cancel: cancel,
    );
    final pagination = _object(info['pagination']);
    final rows = info['data'];
    final maxPage = _integer(pagination['maxpage']);
    final count = _integer(pagination['count']);
    if (_integer(pagination['p']) != page ||
        _integer(pagination['pagesize']) != pageSize ||
        maxPage == null ||
        maxPage < 0 ||
        count == null ||
        count < 0 ||
        rows is! List ||
        rows.length > 100 ||
        (page > maxPage && rows.isNotEmpty)) {
      throw const MissevanException(MissevanFailure.schema);
    }
    final rooms = <String, LiveRoom>{};
    for (final raw in rows) {
      final room = _room(_object(raw));
      rooms.putIfAbsent(room.roomId!, () => room);
    }
    return List.unmodifiable(rooms.values);
  }

  static LiveRoom _room(Map<String, dynamic> row) {
    final id = roomId('${row['room_id']}');
    final open = _integer(_object(row['status'])['open']);
    if (open != 0 && open != 1) throw const MissevanException(MissevanFailure.schema);
    final stats = _object(row['statistics']);
    final score = _integer(stats['score']);
    if (score != null && score < 0) throw const MissevanException(MissevanFailure.schema);
    return LiveRoom(
      platform: 'missevan',
      roomId: id,
      userId: roomId('${row['creator_id']}'),
      link: '$origin/live/$id',
      title: _text(row['name']),
      nick: _text(row['creator_username']),
      cover: _picture(row['cover_url']),
      avatar: _picture(row['creator_iconurl']),
      introduction: _text(row['creator_introduction']),
      notice: _text(row['announcement']),
      area: _text(row['catalog_name']),
      watching: score?.toString() ?? '',
      popularity: score?.toString() ?? '',
      audienceMetricType: AudienceMetricType.popularity,
      status: open == 1,
      liveStatus: open == 1 ? LiveStatus.live : LiveStatus.offline,
    );
  }

  Future<LiveRoom> detail(String input, {bool includeMedia = true, CancelToken? cancel}) async {
    final id = roomId(input);
    final info = await _get('live/$id', cancel: cancel);
    final row = _object(info['room']);
    final room = _room(row);
    if (room.roomId != id) throw const MissevanException(MissevanFailure.schema);
    if (info['creator'] != null) {
      final creator = _object(info['creator']);
      if (roomId('${creator['user_id']}') != room.userId) throw const MissevanException(MissevanFailure.schema);
      room.avatar = _picture(creator['iconurl']);
      room.introduction = _text(creator['introduction']);
    }
    final followers = _integer(_object(row['statistics'])['attention_count']);
    if (followers != null && followers >= 0) room.followers = '$followers';
    if (!room.isLiveNow || !includeMedia) {
      room.data = const <LivePlayQuality>[];
      return room;
    }
    final channel = _object(row['channel']);
    final qualities = <LivePlayQuality>[];
    for (final kind in ['hls', 'flv']) {
      final raw = channel['${kind}_pull_url'];
      if (raw == null || raw == '') continue;
      final url = mediaUrl(_text(raw), kind: kind);
      qualities.add(
        LivePlayQuality(id: kind, quality: kind.toUpperCase(), sort: 2 - qualities.length, data: List<String>.unmodifiable([url])),
      );
    }
    if (qualities.isEmpty) throw const MissevanException(MissevanFailure.schema);
    room.data = List<LivePlayQuality>.unmodifiable(qualities);
    return room;
  }

  static String mediaUrl(String input, {required String kind}) {
    try {
      final uri = Uri.parse(input);
      if (!{'hls', 'flv'}.contains(kind) ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment ||
          (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) ||
          !uri.host.endsWith('.bilivideo.com') ||
          !uri.path.endsWith(kind == 'hls' ? '.m3u8' : '.flv')) {
        throw const MissevanException(MissevanFailure.schema);
      }
      final expires = uri.queryParametersAll['expires'];
      if (expires != null && (expires.length != 1 || !RegExp(r'^[0-9]{10}$').hasMatch(expires.single))) {
        throw const MissevanException(MissevanFailure.schema);
      }
      return uri.replace(scheme: 'https', port: 443).toString();
    } on FormatException {
      throw const MissevanException(MissevanFailure.schema);
    }
  }
}

class MissevanDirectoryPage {
  const MissevanDirectoryPage({required this.rooms, required this.page, required this.maxPage, required this.count});
  final List<LiveRoom> rooms;
  final int page;
  final int maxPage;
  final int count;
  bool get hasMore => page < maxPage;
}

// 3.x's missevan_site.dart ------------------------------------------------------

class MissevanSite {
  MissevanSite({required MissevanApi api}) : _api = api;
  final MissevanApi _api;

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    final result = await _api.directoryPage(page: page, category: category, cancel: cancel);
    return LiveDirectoryPage(rooms: result.rooms, page: result.page, hasMore: result.hasMore);
  }

  String get id => 'missevan';
  String get name => '猫耳 FM';
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async =>
      page == 1 ? [LiveCategory(id: id, name: name, children: await _api.categories())] : [];
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) =>
      _api.directory(page: page, pageSize: pageSize);
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) =>
      _api.directory(page: page, pageSize: pageSize, category: category);

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  static String? _searchRoomId(String input) {
    try {
      return MissevanApi.roomId(input);
    } on MissevanException {
      final uri = Uri.tryParse(input);
      return uri == null ? null : MissevanApi.roomFromUri(uri);
    }
  }

  bool supportsSearchPaginationFor(String keyword) {
    final input = keyword.trim();
    return input.isNotEmpty && _searchRoomId(input) == null && Uri.tryParse(input)?.hasScheme != true;
  }

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (pageSize < 1) return const [];
    final input = keyword.trim();
    if (input.isEmpty) return const [];
    final id = _searchRoomId(input);
    if (id != null) {
      if (page != 1) return const [];
      try {
        return [await _api.detail(id, includeMedia: false, cancel: cancel)];
      } on MissevanException catch (error) {
        if (error.kind == MissevanFailure.notFound) return const [];
        rethrow;
      }
    }
    if (Uri.tryParse(input)?.hasScheme == true) return const [];
    return _api.searchPage(input, page: page, pageSize: pageSize, cancel: cancel);
  }

  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) {
    if (platform != id) throw const MissevanException(MissevanFailure.schema);
    return _api.detail(roomId);
  }

  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) =>
      getRoomDetail(roomId: roomId, platform: platform);
  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) =>
      getRoomDetail(roomId: roomId, platform: platform);
  Future<bool> getLiveStatus({required String platform, required String roomId}) async =>
      (await getRoomDetail(roomId: roomId, platform: platform)).isLiveNow;
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.platform != id) throw const MissevanException(MissevanFailure.schema);
    if (detail.isExplicitlyOfflineNow) return [];
    if (!detail.isLiveNow || detail.data is! List<LivePlayQuality> || (detail.data as List).isEmpty) {
      throw const MissevanException(MissevanFailure.schema);
    }
    return List.unmodifiable(detail.data as List<LivePlayQuality>);
  }

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    for (final current in await getPlayQualites(detail: detail)) {
      if (current.selectionId == quality.selectionId) return List.unmodifiable(current.data as List<String>);
    }
    throw const MissevanException(MissevanFailure.qualityUnavailable);
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

  DateTime? getPlayUrlInvalidAt(String url, {DateTime? now}) {
    try {
      final uri = Uri.parse(url);
      final kind = uri.path.endsWith('.m3u8') ? 'hls' : 'flv';
      final normalized = Uri.parse(MissevanApi.mediaUrl(url, kind: kind));
      final expires = int.tryParse(normalized.queryParameters['expires'] ?? '');
      return expires == null ? null : DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    } on FormatException {
      return null;
    } on MissevanException {
      return null;
    }
  }

  DateTime? getPlayUrlRefreshAt(String url, {DateTime? now}) =>
      getPlayUrlInvalidAt(url, now: now)?.subtract(const Duration(minutes: 1));
}
