// Writes expected.json for the KilaKila samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.15-kilakila.md, "v3 的冻结输出").
//
// The archive has no KilaKila expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below the models is
// 3.x's KilakilaApi, KilakilaLink and KilakilaSite, copied from
// legacy/lib/core/site/kilakila/kilakila_api.dart, kilakila_link.dart and
// kilakila_site.dart (archive/v4). 3.x already injected its transport
// (`KilakilaRequest`), so only that function is replaced: it answers from the
// samples by host, path and query, like the legacy FixtureAdapter, with the
// empty body 3.x read for any status other than 200, and throws a StateError
// for a request without a sample (rethrown, so a harness gap is never taken
// for 3.x's transport failure). Dio's CancelToken, 3.x's LiveRoom, LiveArea,
// LiveCategory, LivePlayQuality, LivePlayUrlResolution and LiveDirectoryPage
// are reduced to the parts these classes use; `i18n` answers 3.x's zh.json.
// KilakilaSite keeps its method bodies; its `extends`/`implements` clause,
// the `@override`s and `getDanmaku` (EmptyDanmaku) are left out, and both
// constructors require the injected transport. The network path
// (`_defaultRequest`, `readBody`) is left out. The share-import branch
// of 3.x's LiveUrlTool._parseLiveUrl (live_url_tool.dart:216-222) is copied
// as `_legacyShareImport`. The output format is the legacy harness's
// (`roomProjection`, `errorProjection`, `{generator, value}`).
//
// 3.x parsed search pages with package:html and decrypted share links with
// package:pointycastle, which are not workspace dependencies. Run it from the
// repository root with a scratch package that has them (3.x's pubspec:
// html ^0.15.4, pointycastle ^4.0.0; generated with html 0.15.6,
// pointycastle 4.0.0, crypto 3.0.7):
//
//   dir=$(mktemp -d)
//   printf 'name: kilakila_legacy\nenvironment:\n  sdk: ^3.13.0\ndependencies:\n  crypto: 3.0.7\n  html: 0.15.6\n  pointycastle: 4.0.0\n' > "$dir/pubspec.yaml"
//   (cd "$dir" && dart pub get)
//   dart --packages="$dir/.dart_tool/package_config.json" fixtures/kilakila/legacy_expected.dart
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';
import 'package:pointycastle/padded_block_cipher/padded_block_cipher_impl.dart';
import 'package:pointycastle/paddings/pkcs7.dart';

const _root = 'fixtures/kilakila';
const _liveOwner = '3674092253247';
const _liveBroadcast = '2268450556051718173';

void main() async {
  for (final (sample, page, type) in [
    ('S01-timeline-hot-p1', 1, '0'),
    ('S01-timeline-hot-p2', 2, '0'),
    ('S01-timeline-hot-last', 55, '0'),
    ('S01-timeline-new-p1', 1, '107'),
  ]) {
    await _timeline(sample, page: page, type: type);
  }
  for (final sample in ['S03-search', 'S03-search-p2', 'S03-search-empty']) {
    await _search(sample);
  }
  await _owner('S04-owner-live', _liveOwner, broadcasts: ['S05-room-live']);
  await _owner('S04-owner-offline', '1775178981381');
  await _owner('S04-owner-notfound', '1');
  await _broadcast('S05-room-live', _liveBroadcast, owners: ['S04-owner-live']);
  await _broadcast('S05-room-replay', '2261269383617708096');
  await _broadcast('S05-room-notfound', '1');
  await _redirect();
  await _vectors();
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

/// 3.x's `KilakilaRequest` over the samples: 3.x read no body for a status
/// other than 200.
Future<({int status, String body})> _fixtureRequest(Uri uri, CancelToken? cancel) async {
  _requests.add(uri);
  for (final meta in _samples) {
    final recorded = Uri.parse((meta['request'] as Map)['url'] as String);
    if (recorded.host == uri.host &&
        recorded.path == uri.path &&
        _sameQuery(recorded.queryParameters, uri.queryParameters)) {
      final status = (meta['response'] as Map)['status'] as int;
      if (status != 200) return (status: status, body: '');
      return (status: 200, body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync());
    }
  }
  throw StateError('No recorded sample for GET $uri');
}

KilakilaApi _api() => KilakilaApi(request: _fixtureRequest);

KilakilaSite _site() => KilakilaSite(api: _api());

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
Future<Map<String, Object?>> _counted<T>(Future<T> Function() body, Object? Function(T value) project) async {
  final before = _requests.length;
  final outcome = await _outcome(body, project);
  return {
    'value': outcome,
    'requests': [for (final uri in _requests.sublist(before)) uri.toString()],
  };
}

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere((key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty));
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

Map<String, dynamic> _snapshotProjection(KilakilaRoomSnapshot room) => {
  'roomId': room.roomId,
  'userId': room.userId,
  'title': room.title,
  'nick': room.nick,
  'cover': room.cover,
  'avatar': room.avatar,
  'statusCode': room.statusCode,
  'goldPrice': room.goldPrice,
  'watchNumber': room.watchNumber,
  'isLive': room.isLive,
  'link': room.link,
  'media': room.media,
};

Object? _linkProjection(KilakilaLink? link) => link == null ? null : {'kind': link.kind.name, 'id': link.id};

/// The KilaKila branch of 3.x's `LiveUrlTool._parseLiveUrl`
/// (live_url_tool.dart:216-222) for one shared URL [raw].
Future<List<String>> _legacyShareImport(String raw, KilakilaApi kilakilaApi) async {
  final cancel = CancelToken();
  final kilakila = KilakilaLink.parse(raw);
  if (kilakila != null) {
    if (kilakila.kind == KilakilaLinkKind.owner) return [kilakila.id, 'kilakila'];
    final owner = await kilakilaApi.ownerFromLink(raw, cancel: cancel);
    if (cancel.isCancelled) return [];
    return [owner.userId, 'kilakila'];
  }
  return [];
}

Future<Map<String, Object?>> _qualities(KilakilaSite site, LiveRoom detail) async {
  final qualities = await site.getPlayQualites(detail: detail);
  return {
    'getPlayQualites': [
      for (final quality in qualities)
        {
          'quality': quality.quality,
          'id': quality.id,
          'sort': quality.sort,
          'getPlayUrls': await site.getPlayUrls(detail: detail, quality: quality),
        },
    ],
  };
}

// Samples ---------------------------------------------------------------------

Future<void> _timeline(String sample, {required int page, required String type}) async {
  _replay([sample]);
  final site = _site();
  final area = LiveArea(platform: 'kilakila', areaType: 'timeline', areaId: type, typeName: '克拉克拉');
  Object? project(LiveDirectoryPage result) => {
    'rooms': _rooms(result.rooms),
    'page': result.page,
    'hasMore': result.hasMore,
  };
  final value = <String, Object?>{
    if (type == '0') 'getDirectoryPage(null)': await _counted(() => site.getDirectoryPage(page: page), project),
    'getDirectoryPage': await _counted(() => site.getDirectoryPage(page: page, category: area), project),
    if (type == '0')
      'getRecommendRooms': await _counted(() => site.getRecommendRooms(page: page, pageSize: 10), _rooms),
    'getCategoryRooms': await _counted(() => site.getCategoryRooms(area, page: page, pageSize: 10), _rooms),
  };
  if (sample == 'S01-timeline-hot-p1') {
    value['getCategores'] = await _outcome(
      () => site.getCategores(1, 30),
      (categories) => [
        for (final category in categories)
          {
            'id': category.id,
            'name': category.name,
            'children': [for (final area in category.children) area.toJson()],
          },
      ],
    );
    value['getCategores(2)'] = await _outcome(() => site.getCategores(2, 30), (categories) => categories.length);
    value['directoryNoticeKey'] = site.directoryNoticeKey;
  }
  _write(
    sample,
    'KilakilaSite.getDirectoryPage + getRecommendRooms + getCategoryRooms (page size 10)'
        '${sample == 'S01-timeline-hot-p1' ? ' + getCategores + directoryNoticeKey' : ''}',
    value,
  );
}

Future<void> _search(String sample) async {
  _replay([sample]);
  final segments = Uri.parse((_meta(sample)['request'] as Map)['url'] as String).pathSegments;
  final keyword = segments[3];
  final page = segments.length > 5 ? int.parse(segments[5]) : 1;
  final site = _site();
  _write(sample, 'KilakilaSite.searchRooms (page size 20) + supportsSearchPaginationFor', {
    'searchRooms': await _counted(() => site.searchRooms(keyword, page: page, pageSize: 20), _rooms),
    'supportsSearchPaginationFor': site.supportsSearchPaginationFor(keyword),
  });
}

Future<void> _owner(String sample, String uid, {List<String> broadcasts = const []}) async {
  _replay([sample, ...broadcasts]);
  final site = _site();
  final value = <String, Object?>{
    'getRoomDetailForRefresh': await _counted(
      () => site.getRoomDetailForRefresh(roomId: uid, platform: 'kilakila'),
      _roomProjection,
    ),
    'getRoomDetail': await _counted(() => site.getRoomDetail(roomId: uid, platform: 'kilakila'), _roomProjection),
    'getRoomDetailForRecording': await _counted(
      () => site.getRoomDetailForRecording(roomId: uid, platform: 'kilakila'),
      _roomProjection,
    ),
    'getLiveStatus': await _counted(() => site.getLiveStatus(roomId: uid, platform: 'kilakila'), (live) => live),
    'searchRooms(uid)': await _counted(() => site.searchRooms(uid), _rooms),
    'searchRooms(ownerUrl)': await _counted(() => site.searchRooms(KilakilaSite.ownerUrl(uid)), _rooms),
    'supportsSearchPaginationFor': site.supportsSearchPaginationFor(uid),
  };
  try {
    final detail = await site.getRoomDetail(roomId: uid, platform: 'kilakila');
    value.addAll(await _qualities(site, detail));
    final quality = (await site.getPlayQualites(detail: detail)).first;
    value['resolvePlayUrlsForRecoveryRaw'] = await _counted(
      () => site.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: quality),
      (resolution) => {'urls': resolution.urls, 'appliedQualityData': resolution.appliedQualityData},
    );
  } on Object catch (error) {
    value['getPlayQualites'] = _errorProjection(error);
  }
  _write(
    sample,
    'KilakilaSite.getRoomDetailForRefresh / getRoomDetail / getRoomDetailForRecording / getLiveStatus / '
        'searchRooms($uid and its owner URL) + getPlayQualites + getPlayUrls + resolvePlayUrlsForRecoveryRaw',
    value,
  );
}

Future<void> _broadcast(String sample, String roomId, {List<String> owners = const []}) async {
  _replay([sample, ...owners]);
  final api = _api();
  final value = <String, Object?>{
    'detail(playback: false)': await _counted(() => api.detail(roomId, playback: false), _snapshotProjection),
    'detail(playback: true)': await _counted(() => api.detail(roomId), _snapshotProjection),
  };
  var generator = 'KilakilaApi.detail(playback: false / true)';
  if (owners.isNotEmpty || sample == 'S05-room-notfound') {
    final link = '${KilakilaApi.origin}/room/$roomId';
    value['shareImport'] = await _counted(() => _legacyShareImport(link, api), (result) => result);
    generator += ' + LiveUrlTool share import of ${KilakilaApi.origin}/room/$roomId';
  }
  _write(sample, generator, value);
}

Future<void> _redirect() async {
  const sample = 'S06-room-redirect';
  final meta = _meta(sample);
  final location = ((meta['response'] as Map)['headers'] as Map)['location'] as String;
  final requested = (meta['request'] as Map)['url'] as String;
  _replay(['S05-room-live', 'S04-owner-live']);
  final api = _api();
  _write(sample, 'KilakilaLink.parse of the request URL and the Location + LiveUrlTool share import of the Location', {
    'KilakilaLink.parse(request)': _linkProjection(KilakilaLink.parse(requested)),
    'KilakilaLink.parse(location)': _linkProjection(KilakilaLink.parse(location)),
    'shareImport(location)': await _counted(() => _legacyShareImport(location, api), (result) => result),
  });
}

Future<void> _vectors() async {
  final vectors = (jsonDecode(File('$_root/S09-share-vectors/vectors.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();
  _write('S09-share-vectors', 'KilakilaLink.parse of every vector url', [
    for (final vector in vectors) {'name': vector['name'], 'parse': _linkProjection(KilakilaLink.parse(vector['url']))},
  ]);
}

// 3.x models (the parts the KilaKila classes use) -----------------------------

class CancelToken {
  bool isCancelled = false;
}

String i18n(String key) =>
    const {'site_kilakila': '克拉克拉', 'kilakila_hot': '热门直播', 'kilakila_newcomers': '萌星推荐'}[key] ?? key;

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

// 3.x's kilakila_api.dart ------------------------------------------------------

enum KilakilaFailure {
  transport,
  access,
  rateLimited,
  notFound,
  service,
  schema,
  cancelled,
  historicalReplay,
  restricted,
  stateUnsupported,
  mediaUnavailable,
}

class KilakilaException implements Exception {
  const KilakilaException(this.kind);
  final KilakilaFailure kind;
  @override
  String toString() => 'Kilakila ${kind.name}';
}

typedef KilakilaRequest = Future<({int status, String body})> Function(Uri uri, CancelToken? cancel);

/// A current room/broadcast and its distinct owner. Neither a share room ID nor
/// an unknown status is promoted to a permanent channel identity/offline state.
class KilakilaRoomSnapshot {
  KilakilaRoomSnapshot({
    required this.roomId,
    required this.userId,
    required this.title,
    required this.nick,
    required this.cover,
    required this.avatar,
    required this.statusCode,
    required this.goldPrice,
    required this.watchNumber,
    Map<String, String> media = const {},
  }) : media = Map.unmodifiable(media);

  final String roomId;
  final String userId;
  final String title;
  final String nick;
  final String cover;
  final String avatar;
  final int statusCode;
  final int goldPrice;
  // Keep the platform field name until its audience semantics are verified.
  final int? watchNumber;
  final Map<String, String> media;
  bool get isLive => statusCode == 4;
  String get link => '${KilakilaApi.origin}/room/$roomId';
}

class KilakilaDirectoryPage {
  KilakilaDirectoryPage({required Iterable<KilakilaRoomSnapshot> rooms, required this.page, required this.hasMore})
    : rooms = List.unmodifiable(rooms);
  final List<KilakilaRoomSnapshot> rooms;
  final int page;
  final bool hasMore;
}

/// A public anchor page keyed by durable UID. A missing advertised broadcast
/// differs from a failed request or an unrecognized broadcast state.
class KilakilaOwnerSnapshot {
  const KilakilaOwnerSnapshot({required this.userId, required this.nick, required this.avatar, this.currentRoom});
  final String userId;
  final String nick;
  final String avatar;
  final KilakilaRoomSnapshot? currentRoom;
}

/// Anonymous official website contracts used by the UID-based LiveSite.
/// Owner lookup and broadcast identity are separate from media resolution.
/// No raw response/push-flow URL is retained in DTOs.
class KilakilaApi {
  KilakilaApi({required KilakilaRequest request}) : _request = request;
  static const origin = 'https://live.kilakila.cn';
  static const ownerOrigin = 'https://live.hongrenshuo.com.cn';
  static const responseLimit = 1024 * 1024;
  static const playHeaders = {'Referer': '$origin/', 'User-Agent': 'Mozilla/5.0'};
  final KilakilaRequest _request;

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
    required bool wrapped,
    CancelToken? cancel,
  }) async {
    var result = await _json(Uri.parse('$origin$path').replace(queryParameters: query), cancel);
    if (wrapped) {
      _businessCode(result['code']);
      result = _object(_object(result['data'])['body']);
    }
    final header = _object(result['h']);
    _businessCode(header['code'], roomDetail: !wrapped && path == '/LiveRoom/getRoomInfo');
    if (header['success'] != true) throw const KilakilaException(KilakilaFailure.schema);
    return result;
  }

  Future<String> _fetch(Uri uri, CancelToken? cancel) async {
    if (cancel?.isCancelled == true) throw const KilakilaException(KilakilaFailure.cancelled);
    late final ({int status, String body}) response;
    try {
      response = await _request(uri, cancel);
    } catch (error) {
      if (cancel?.isCancelled == true) throw const KilakilaException(KilakilaFailure.cancelled);
      if (error is KilakilaException) rethrow;
      // The harness has no network: a request without a sample is a harness
      // error, not 3.x's transport failure.
      if (error is StateError) rethrow;
      throw const KilakilaException(KilakilaFailure.transport);
    }
    if (cancel?.isCancelled == true) throw const KilakilaException(KilakilaFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      401 || 403 => KilakilaFailure.access,
      404 => KilakilaFailure.notFound,
      429 => KilakilaFailure.rateLimited,
      >= 500 => KilakilaFailure.service,
      _ => KilakilaFailure.transport,
    };
    if (failure != null) throw KilakilaException(failure);
    if (response.body.length > responseLimit || utf8.encode(response.body).length > responseLimit) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    return response.body;
  }

  Future<Map<String, dynamic>> _json(Uri uri, CancelToken? cancel) async {
    try {
      return _object(jsonDecode(await _fetch(uri, cancel)));
    } on FormatException {
      throw const KilakilaException(KilakilaFailure.schema);
    }
  }

  /// Official website user search. Pages are server-sized; profile cards do
  /// not disclose the current broadcast state, so callers keep it unknown.
  Future<List<KilakilaOwnerSnapshot>> searchOwners(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    CancelToken? cancel,
  }) async {
    final query = keyword.trim();
    if (page < 1 || page > 10000 || pageSize < 1 || pageSize > 100 || query.length > 100) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    if (query.isEmpty) return const [];
    final uri = Uri(
      scheme: 'https',
      host: 'live.kilakila.cn',
      pathSegments: [
        'aboutus',
        'serach',
        'kw',
        query,
        if (page > 1) ...['p', '$page'],
      ],
    );
    final document = html.parse(await _fetch(uri, cancel));
    final list = document.querySelector('.userList');
    if (list == null || list.children.length > 100) throw const KilakilaException(KilakilaFailure.schema);
    final profiles = <String, KilakilaOwnerSnapshot>{};
    for (final anchor in list.children.where((element) => element.localName == 'a')) {
      final path = anchor.attributes['href'] ?? '';
      final match = RegExp(r'^/zhubo/([1-9][0-9]{0,31})$').firstMatch(path);
      final nick = anchor.querySelector('.anchor-name')?.text.trim() ?? '';
      if (match == null || nick.isEmpty) throw const KilakilaException(KilakilaFailure.schema);
      final uid = id(match.group(1)!);
      profiles.putIfAbsent(
        uid,
        () => KilakilaOwnerSnapshot(
          userId: uid,
          nick: nick,
          avatar: _picture(anchor.querySelector('.anchorHeaderImg img')?.attributes['src']),
        ),
      );
    }
    return List.unmodifiable(profiles.values);
  }

  static void _businessCode(Object? value, {bool roomDetail = false}) {
    final code = _integer(value);
    if (code == null) throw const KilakilaException(KilakilaFailure.schema);
    if (roomDetail && code == 5966) throw const KilakilaException(KilakilaFailure.historicalReplay);
    if (code != 200) throw const KilakilaException(KilakilaFailure.service);
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) throw const KilakilaException(KilakilaFailure.schema);
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _rows(Object? value) {
    if (value is! List || value.length > 1000) throw const KilakilaException(KilakilaFailure.schema);
    return value.map(_object).toList();
  }

  static String _text(Object? value) => value is String ? value.trim() : '';
  static int? _integer(Object? value) => value is int
      ? value
      : value is String
      ? int.tryParse(value)
      : null;
  static int _nonnegative(Object? value) {
    final number = _integer(value);
    if (number == null || number < 0) throw const KilakilaException(KilakilaFailure.schema);
    return number;
  }

  static String id(String value) {
    if (!RegExp(r'^[1-9][0-9]{0,31}$').hasMatch(value)) throw const KilakilaException(KilakilaFailure.schema);
    return value;
  }

  static String _id(Object? value) {
    // JSON numbers above JS's exact range may already be rounded upstream.
    if (value is int && value > 0 && value <= 9007199254740991) return '$value';
    if (value is String) return id(value);
    throw const KilakilaException(KilakilaFailure.schema);
  }

  static String? numericRoomFromUri(Uri uri) {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        !{'live.kilakila.cn', 'www.hongdoufm.com'}.contains(uri.host) ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    try {
      // Opaque/signed links use the separate KilakilaLink codec. Never
      // accidentally treat the encoded payload as a durable numeric room ID.
      final query = uri.queryParametersAll;
      if (query.containsKey('_specific_parameter')) return null;
      if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'room' && !query.containsKey('id')) {
        return id(uri.pathSegments.last);
      }
      if (uri.path == '/PcLive/index/detail' && query['id']?.length == 1) return id(query['id']!.single);
    } on FormatException {
      return null;
    } on KilakilaException {
      return null;
    }
    return null;
  }

  static String? numericOwnerFromUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != 'live.hongrenshuo.com.cn' ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.hasQuery) {
      return null;
    }
    try {
      final parts = uri.pathSegments;
      if (parts.length == 4 && parts[0] == 'index' && parts[1] == 'roomuser' && parts[2] == 'uid') {
        return id(parts[3]);
      }
    } on FormatException {
      return null;
    } on KilakilaException {
      return null;
    }
    return null;
  }

  static String _picture(Object? value) {
    final text = _text(value);
    final uri = Uri.tryParse(text);
    return uri != null && {'http', 'https'}.contains(uri.scheme) && uri.host.isNotEmpty && uri.userInfo.isEmpty
        ? text
        : '';
  }

  static String? mediaUrl(Object? value, {required String roomId, required String protocol}) {
    if (!{'flv', 'hls'}.contains(protocol)) return null;
    final text = _text(value);
    if (text.length > 8192) return null;
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'pull.live.hongrenshuo.com.cn' ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.path != '/hrs/${id(roomId)}.${protocol == 'flv' ? 'flv' : 'm3u8'}') {
      return null;
    }
    try {
      final auth = uri.queryParametersAll['auth_key'];
      if (auth?.length != 1 || auth!.single.isEmpty || auth.single.length > 1024) return null;
      return text;
    } on FormatException {
      return null;
    }
  }

  static KilakilaRoomSnapshot _snapshot(
    Map<String, dynamic> room,
    Map<String, dynamic> owner, {
    bool playback = false,
  }) {
    final roomId = _id(room['roomIdStr']);
    final userId = _id(room['uid']);
    if (_id(owner['id']) != userId || _text(room['title']).isEmpty || _text(owner['nickname']).isEmpty) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    final status = _nonnegative(room['status']);
    final price = _nonnegative(room['goldPrice']);
    final media = <String, String>{};
    if (playback) {
      if (price != 0) throw const KilakilaException(KilakilaFailure.restricted);
      if (status != 4) throw const KilakilaException(KilakilaFailure.stateUnsupported);
      for (final entry in {'flv': 'flvPlayUrl', 'hls': 'hlsPlayUrl'}.entries) {
        final url = mediaUrl(room[entry.value], roomId: roomId, protocol: entry.key);
        if (url != null) media[entry.key] = url;
      }
      if (media.isEmpty) throw const KilakilaException(KilakilaFailure.mediaUnavailable);
    }
    final watching = _integer(room['watchNumber']);
    final cover = _picture(room['backPic']);
    return KilakilaRoomSnapshot(
      roomId: roomId,
      userId: userId,
      title: _text(room['title']),
      nick: _text(owner['nickname']),
      cover: cover.isNotEmpty ? cover : _picture(room['defaultBackgroundPicUrl']),
      avatar: _picture(owner['headPortraitUrl']),
      statusCode: status,
      goldPrice: price,
      watchNumber: watching != null && watching >= 0 ? watching : null,
      media: media,
    );
  }

  static List<KilakilaRoomSnapshot> _directoryRooms(Object? data, {bool includeRisingStars = false}) {
    final result = <KilakilaRoomSnapshot>[];
    final seen = <String>{};
    for (final row in _rows(data)) {
      final type = _nonnegative(row['dataType']);
      // The official type=107 rising-star list uses dataType=2 for the same
      // roomResq/userResp live-card shape. Keep this exception scoped to that
      // timeline; every accepted row still goes through full identity/schema
      // checks below. Do not infer media kind or live state from dataType.
      if (type != 8 && !(includeRisingStars && type == 2)) continue;
      final room = _snapshot(_object(row['roomResq']), _object(row['userResp']));
      if (seen.add(room.roomId)) result.add(room);
    }
    return result;
  }

  Future<KilakilaDirectoryPage> directory({int page = 1, int pageSize = 10, int type = 0, CancelToken? cancel}) async {
    if (page < 1 || page > 100000 || pageSize < 1 || pageSize > 100 || !{0, 107}.contains(type)) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    final envelope = await _get(
      '/pcLive/timeline',
      wrapped: true,
      cancel: cancel,
      query: {'tag': '0', 'type': '$type', 'genderType': '0', 'pageNo': '$page', 'pageSize': '$pageSize'},
    );
    final body = _object(envelope['b']);
    if (_integer(body['pageNo']) != page || _integer(body['pageSize']) != pageSize || body['isLastPage'] is! bool) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    return KilakilaDirectoryPage(
      rooms: _directoryRooms(body['data'], includeRisingStars: type == 107),
      page: page,
      hasMore: !(body['isLastPage'] as bool),
    );
  }

  Future<List<KilakilaRoomSnapshot>> recommendations({CancelToken? cancel}) async {
    final envelope = await _get('/pcLive/recommend', wrapped: true, cancel: cancel);
    // The real successful response can omit b entirely. Only this optional
    // showcase has this contract; a missing timeline/room body is not empty.
    return List.unmodifiable(envelope['b'] == null ? <KilakilaRoomSnapshot>[] : _directoryRooms(envelope['b']));
  }

  Future<KilakilaRoomSnapshot> detail(
    String roomId, {
    bool playback = true,
    String? expectedUserId,
    CancelToken? cancel,
  }) async {
    final requested = id(roomId);
    final owner = expectedUserId == null ? null : id(expectedUserId);
    final envelope = await _get('/LiveRoom/getRoomInfo', wrapped: false, cancel: cancel, query: {'roomId': requested});
    final room = _object(envelope['b']);
    if (_id(room['roomIdStr']) != requested || (owner != null && _id(room['uid']) != owner)) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    return _snapshot(room, _object(room['userInfo']), playback: playback);
  }

  Future<KilakilaOwnerSnapshot> owner(String userId, {CancelToken? cancel}) async {
    final requested = id(userId);
    final envelope = await _json(
      Uri.parse('$ownerOrigin/Tg/personalH5').replace(queryParameters: {'uid': requested}),
      cancel,
    );
    // The public profile endpoint uses 1013 for an unknown account. Other
    // business failures (including code 1) remain service errors.
    if (_integer(envelope['code']) == 1013) throw const KilakilaException(KilakilaFailure.notFound);
    _businessCode(envelope['code']);
    final body = _object(envelope['data']);
    final user = _object(body['userResp']);
    final card = _object(body['liveCard']);
    final nick = _text(user['nickname']);
    if (nick.isEmpty || (user.containsKey('id') && _id(user['id']) != requested)) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    KilakilaRoomSnapshot? current;
    // Observed empty cards contain only these routing defaults. Missing/null,
    // partial room metadata and unknown card forms are not successful empties.
    if (card.keys.every((key) => {'roomSourceType', 'recommendSource'}.contains(key))) {
      for (final value in card.values) {
        _nonnegative(value);
      }
    } else {
      // userResp has no UID on this endpoint; the current card's own UID must
      // match the requested anchor. Never derive identity from nickname/avatar.
      if (_id(card['uid']) != requested) throw const KilakilaException(KilakilaFailure.schema);
      current = _snapshot(card, {...user, 'id': requested});
    }
    return KilakilaOwnerSnapshot(
      userId: requested,
      nick: nick,
      avatar: _picture(user['headPortraitUrl']),
      currentRoom: current,
    );
  }

  /// Re-resolve the anchor each time, then bind the current broadcast detail to
  /// that same owner. No stale broadcast cache, directory scan or ID guessing.
  Future<KilakilaRoomSnapshot?> detailForOwner(String userId, {bool playback = true, CancelToken? cancel}) async {
    final profile = await owner(userId, cancel: cancel);
    final current = profile.currentRoom;
    if (current == null) return null;
    return detail(current.roomId, expectedUserId: profile.userId, playback: playback, cancel: cancel);
  }

  /// Convert a supported public link to the anchor identity before persisting
  /// a favorite. A historical broadcast that cannot identify its owner remains
  /// an explicit error, rather than a guessed UID or a fake offline favorite.
  Future<KilakilaOwnerSnapshot> ownerFromLink(String value, {CancelToken? cancel}) async {
    final link = KilakilaLink.parse(value);
    if (link == null) throw const KilakilaException(KilakilaFailure.schema);
    if (link.kind == KilakilaLinkKind.owner) return owner(link.id, cancel: cancel);
    final broadcast = await detail(link.id, playback: false, cancel: cancel);
    return owner(broadcast.userId, cancel: cancel);
  }
}

// 3.x's kilakila_link.dart -----------------------------------------------------

enum KilakilaLinkKind { broadcast, owner }

class KilakilaLink {
  const KilakilaLink(this.kind, this.id);
  final KilakilaLinkKind kind;
  final String id;

  // Public website codec constants, not account credentials or app signing
  // secrets. Provenance: official uxin-security-url-crypto-v2.min.js, SHA-256
  // 2a031560d9ccd3770ff57969b8818e5eafd6d8a1e4f54c87e0f4bd983d4607e2.
  static const _readKeys = ['7cdyGRc6Sa93ilPt', 'c98be79a4347bc97'];
  static const _iv = '93x0ue23c2c9h8km';
  static const _signaturePrefix = r'pR@Wv%Wju@Pl&bKc$GyUrPeO';

  static KilakilaLink? parse(String value) {
    if (value.length > 8192) return null;
    final input = value.trim();
    if (RegExp(r'[\x00-\x20\x7f]').hasMatch(input) || RegExp(r'%(?![0-9a-fA-F]{2})').hasMatch(input)) {
      return null;
    }
    final uri = Uri.tryParse(input);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    final roomHost = {'live.kilakila.cn', 'www.hongdoufm.com'}.contains(uri.host);
    final ownerHost = uri.host == 'live.hongrenshuo.com.cn' && uri.scheme == 'https';
    if (!roomHost && !ownerHost) return null;
    // Dart normalizes escaped unreserved path characters. The official codec
    // binds the original route, so do not sign a silently rewritten prefix.
    final rawPath = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*://[^/?#]+([^?#]*)').firstMatch(input)?.group(1);
    if (rawPath == null) return null;
    try {
      final query = uri.queryParametersAll;
      if (query.values.any((v) => v.length != 1)) return null;
      final publicOwnerPath = roomHost && rawPath.startsWith('/zhubo/');
      if (publicOwnerPath && uri.hasQuery) return null;
      final pathPrefix = ownerHost ? '/index/roomuser/uid/' : (publicOwnerPath ? '/zhubo/' : '/room/');
      final isPath = rawPath.startsWith(pathPrefix);
      final isDetail = roomHost && {'/PcLive/index/detail', '/PcLive/index/detail/'}.contains(rawPath);
      if (!isPath && !isDetail) return null;
      final kind = ownerHost || publicOwnerPath ? KilakilaLinkKind.owner : KilakilaLinkKind.broadcast;
      String payload;
      if (isPath) {
        if (query.containsKey('id') || query.containsKey('uid') || query.containsKey('_specific_parameter')) {
          return null;
        }
        payload = Uri.decodeComponent(rawPath.substring(pathPrefix.length));
        if (payload.contains('/')) return null;
        if (_validId(payload)) return KilakilaLink(kind, payload);
      } else {
        if (query.containsKey('_specific_parameter')) {
          if (query.containsKey('id') || query.containsKey('sign')) return null;
          payload = query['_specific_parameter']!.single;
        } else {
          final id = query['id']?.single;
          return id != null && _validId(id) ? KilakilaLink(kind, id) : null;
        }
      }
      if (payload.length > 4096 || !RegExp(r'^[A-Za-z0-9_+/\-]+={0,2}$').hasMatch(payload)) {
        return null;
      }
      final bytes = base64Url.decode(base64Url.normalize(payload));
      if (bytes.isEmpty || bytes.length % 16 != 0) return null;
      for (final key in _readKeys) {
        try {
          final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
            ..init(
              false,
              PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
                ParametersWithIV(
                  KeyParameter(Uint8List.fromList(utf8.encode(key))),
                  Uint8List.fromList(utf8.encode(_iv)),
                ),
                null,
              ),
            );
          final plain = utf8.decode(cipher.process(bytes));
          final params = _parameters(plain);
          if (params == null) continue;
          final id = params['id'];
          final sign = params['sign'];
          if (id == null || !_validId(id) || sign == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(sign)) {
            continue;
          }
          var base = '${uri.origin}${isPath ? pathPrefix : '$rawPath?'}';
          String canonical;
          if (isPath && params.length == 2) {
            canonical = id;
          } else {
            if (isPath) base += '$id?';
            final keys = params.keys.where((k) => k != 'sign' && (!isPath || k != 'id')).toList()..sort();
            canonical = keys.map((k) => '$k=${params[k]}').join('&');
          }
          final expected = md5.convert(utf8.encode('$_signaturePrefix$base$canonical')).toString();
          if (expected == sign) return KilakilaLink(kind, id);
        } on ArgumentError {
          continue;
        } on FormatException {
          continue;
        } on InvalidCipherTextException {
          continue;
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static bool _validId(String value) => RegExp(r'^[1-9][0-9]{0,31}$').hasMatch(value);

  static Map<String, String>? _parameters(String plain) {
    if (plain.isEmpty || plain.length > 4096 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(plain)) {
      return null;
    }
    final result = <String, String>{};
    final question = plain.indexOf('?');
    var query = plain;
    if (question >= 0) {
      if (plain.indexOf('?', question + 1) >= 0) return null;
      final id = plain.substring(0, question);
      if (!_validId(id)) return null;
      result['id'] = id;
      query = plain.substring(question + 1);
    }
    for (final pair in query.split('&')) {
      final equal = pair.indexOf('=');
      if (equal <= 0 || result.length >= 32) return null;
      var key = pair.substring(0, equal);
      var value = pair.substring(equal + 1);
      // The official codec uses URLSearchParams for ID?query payloads, but
      // preserves raw parameter values for its detail-page query-string form.
      if (question >= 0) {
        key = Uri.decodeQueryComponent(key);
        value = Uri.decodeQueryComponent(value);
      } else if (value.contains('=')) {
        return null;
      }
      if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,63}$').hasMatch(key) ||
          value.length > 1024 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
          result.containsKey(key)) {
        return null;
      }
      result[key] = value;
    }
    return result;
  }
}

// 3.x's kilakila_site.dart (its extends/implements clause, @override and
// getDanmaku left out) ---------------------------------------------------------

/// App identities are anchor UIDs, never one-broadcast IDs or display numbers.
class KilakilaSite {
  KilakilaSite({required KilakilaApi api}) : _api = api;
  final KilakilaApi _api;
  String get id => 'kilakila';
  String get name => i18n('site_kilakila');
  String get directoryNoticeKey => 'kilakila_directory_scope';

  static String ownerUrl(String uid) => '${KilakilaApi.ownerOrigin}/index/roomuser/uid/${KilakilaApi.id(uid)}';

  static LiveRoom _room(KilakilaRoomSnapshot snapshot) => LiveRoom(
    platform: 'kilakila',
    roomId: snapshot.userId,
    userId: snapshot.userId,
    title: snapshot.title,
    nick: snapshot.nick,
    cover: snapshot.cover,
    avatar: snapshot.avatar,
    link: ownerUrl(snapshot.userId),
    watching: '',
    audienceMetricType: AudienceMetricType.unknown,
    status: snapshot.isLive ? true : null,
    liveStatus: snapshot.isLive ? LiveStatus.live : LiveStatus.unknown,
    // watchNumber has no verified concurrent-viewer semantics. Broadcast IDs
    // and signed media remain ephemeral; favorites/backup retain only the UID.
    data: snapshot.media.isEmpty
        ? null
        : [
            for (final entry in snapshot.media.entries)
              LivePlayQuality(id: entry.key, quality: entry.key.toUpperCase(), data: <String>[entry.value]),
          ],
  );

  static LiveRoom _profileRoom(KilakilaOwnerSnapshot owner) => LiveRoom(
    platform: 'kilakila',
    roomId: owner.userId,
    userId: owner.userId,
    title: owner.nick,
    nick: owner.nick,
    avatar: owner.avatar,
    link: ownerUrl(owner.userId),
    watching: '',
    audienceMetricType: AudienceMetricType.unknown,
    status: null,
    liveStatus: LiveStatus.unknown,
  );

  int _type(LiveArea? category) {
    if (category == null) return 0;
    if (category.platform != id || category.areaType != 'timeline' || !{'0', '107'}.contains(category.areaId)) {
      throw const KilakilaException(KilakilaFailure.schema);
    }
    return int.parse(category.areaId!);
  }

  Future<LiveDirectoryPage> _directory({
    required int page,
    required int pageSize,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    final result = await _api.directory(page: page, pageSize: pageSize, type: _type(category), cancel: cancel);
    final seen = <String>{};
    return LiveDirectoryPage(
      page: result.page,
      hasMore: result.hasMore,
      rooms: result.rooms.where((room) => seen.add(room.userId)).map(_room),
    );
  }

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) =>
      _directory(page: page, pageSize: 10, category: category, cancel: cancel);
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await _directory(page: page, pageSize: pageSize)).rooms;
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      (await _directory(page: page, pageSize: pageSize, category: category)).rooms;
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async => page == 1
      ? [
          LiveCategory(
            id: id,
            name: name,
            children: [
              for (final entry in {'0': 'kilakila_hot', '107': 'kilakila_newcomers'}.entries)
                LiveArea(
                  platform: id,
                  areaType: 'timeline',
                  typeName: name,
                  areaId: entry.key,
                  areaName: i18n(entry.value),
                ),
            ],
          ),
        ]
      : [];

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  static KilakilaLink? _searchLink(String input) => RegExp(r'^[1-9][0-9]{0,31}$').hasMatch(input)
      ? KilakilaLink(KilakilaLinkKind.owner, input)
      : KilakilaLink.parse(input);

  bool supportsSearchPaginationFor(String keyword) {
    final input = keyword.trim();
    return input.isNotEmpty &&
        _searchLink(input) == null &&
        !RegExp(r'^[0-9]+$').hasMatch(input) &&
        Uri.tryParse(input)?.hasScheme != true;
  }

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page < 1 || pageSize < 1) throw const KilakilaException(KilakilaFailure.schema);
    final input = keyword.trim();
    final link = _searchLink(input);
    if (link == null) {
      if (!supportsSearchPaginationFor(input)) return const [];
      return List.unmodifiable([
        for (final owner in await _api.searchOwners(input, page: page, pageSize: pageSize, cancel: cancel))
          _profileRoom(owner),
      ]);
    }
    if (link.kind != KilakilaLinkKind.owner || page > 1) return const [];
    try {
      final owner = await _api.owner(link.id, cancel: cancel);
      final current = owner.currentRoom;
      if (current != null) return [_room(current)];
      return [_profileRoom(owner)];
    } on KilakilaException catch (error) {
      if (error.kind == KilakilaFailure.notFound) return const [];
      rethrow;
    }
  }

  Future<LiveRoom> _detail(String uid, String platform, {required bool playback}) async {
    if (platform != id) throw const KilakilaException(KilakilaFailure.schema);
    final owner = await _api.owner(uid);
    final current = owner.currentRoom;
    if (current == null) {
      // No advertised broadcast is not an authoritative offline declaration.
      return LiveRoom(
        platform: id,
        roomId: owner.userId,
        userId: owner.userId,
        nick: owner.nick,
        avatar: owner.avatar,
        link: ownerUrl(owner.userId),
        watching: '',
        audienceMetricType: AudienceMetricType.unknown,
        status: null,
        liveStatus: LiveStatus.unknown,
      );
    }
    if (!playback) return _room(current);
    final detail = await _api.detail(current.roomId, expectedUserId: owner.userId);
    return _room(detail);
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
    if (detail.platform != id ||
        !detail.isLiveNow ||
        detail.data is! List<LivePlayQuality> ||
        (detail.data as List).isEmpty) {
      throw const KilakilaException(KilakilaFailure.mediaUnavailable);
    }
    return List.unmodifiable(detail.data as List<LivePlayQuality>);
  }

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    for (final current in await getPlayQualites(detail: detail)) {
      if (current.selectionId == quality.selectionId) return List.unmodifiable(current.data as List<String>);
    }
    throw const KilakilaException(KilakilaFailure.mediaUnavailable);
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
