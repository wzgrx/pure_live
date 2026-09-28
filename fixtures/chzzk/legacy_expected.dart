// Writes expected.json for the CHZZK samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.20-chzzk.md, "样本与 v3 的冻结输出").
//
// The archive has no CHZZK expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below is 3.x's
// ChzzkApi, ChzzkLink and ChzzkSite, copied from legacy/lib/core/site/chzzk/
// (archive/v4), and 3.x's HlsMasterPlaylist from
// legacy/lib/core/common/hls_master_selection.dart (the parse part). 3.x
// already injected its transport (`ChzzkRequest`), so only that function is
// replaced: it answers from the samples by host, path and the query other
// than `size` and the scrubbed signatures (`hdnts`, `vp`), with the empty
// body 3.x read for any status other than 200, and throws a StateError for a
// request without a sample (`_read` lets that StateError through instead of
// turning it into `transport`, so a missing sample fails the run).
// `_defaultRequest`, `readBody` (network path only) and Dio's CancelToken
// are left out; `withRequestCancellation` just runs its body. `i18n`
// returns 3.x's zh.json text. 3.x's LiveRoom, LiveArea, LiveCategory,
// LivePlayQuality and LiveDirectoryPage are reduced to the parts these
// classes use. The output format is the legacy harness's
// (`roomProjection`, `errorProjection`, `{generator, value}`); every entry
// also records its number of requests.
//
// Two scenarios have no recorded channel answer: the region-locked and the
// adult live (`S06-live-detail-region`, `-adult`) were captured without
// their `/service/v1/channels/<id>`. The harness answers that request with
// the live-detail's own `channel` object (no description, no follower
// count), as the site test does.
//
// Run from the repository root: dart run fixtures/chzzk/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint, unused_field
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/chzzk';

const _live = 'af3323d30e11ae42c39d7203c7e07fa2';
const _offline = '12bba8d480ba0ffaf85656afd76fa792';
const _region = '75cbf189b3bb8f9f687d2aca0d0a382b';
const _adult = '7ce8032370ac5121dcabce7bad375ced';
const _missing = '00000000000000000000000000000000';

void main() async {
  await _directory();
  await _search('S04-search-channels', '배틀');
  await _search('S04-search-empty', 'zxqvfixturenoresult');
  for (final (sample, id) in [
    ('S05-channel-live', _live),
    ('S05-channel-offline', _offline),
    ('S05-channel-notfound', _missing),
  ]) {
    await _channel(sample, id);
  }
  await _room('S06-live-detail-live', [
    'S05-channel-live',
    'S06-live-detail-live',
    'S07-master-hls',
    'S07-master-llhls',
  ], _live);
  await _room('S06-live-detail-offline', [
    'S05-channel-offline',
    'S06-live-detail-offline',
  ], _offline);
  await _room(
    'S06-live-detail-region',
    ['S06-live-detail-region'],
    _region,
    channelFromLiveDetail: true,
  );
  await _room(
    'S06-live-detail-adult',
    ['S06-live-detail-adult'],
    _adult,
    channelFromLiveDetail: true,
  );
  await _liveDetailMissing();
  await _master('S07-master-hls', 'HLS');
  await _master('S07-master-llhls', 'LLHLS');
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final Map<String, String> _synthetic = {};
final List<Uri> _requests = [];

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

const _unmatched = {'size', 'hdnts', 'vp'};

Map<String, String> _query(Uri uri) => {
  for (final entry in uri.queryParameters.entries)
    if (!_unmatched.contains(entry.key)) entry.key: entry.value,
};

bool _sameQuery(Uri a, Uri b) {
  final left = _query(a);
  final right = _query(b);
  return left.length == right.length &&
      left.entries.every((entry) => right[entry.key] == entry.value);
}

/// 3.x's `_defaultRequest` over the samples: no redirect following, and the
/// body is read only for a 200.
Future<({int status, String body})> _replay(
  Uri uri,
  CancelToken? cancel,
) async {
  _requests.add(uri);
  final synthetic = _synthetic[uri.path];
  if (synthetic != null) return (status: 200, body: synthetic);
  final meta = _samples.firstWhere((meta) {
    final recorded = Uri.parse((meta['request'] as Map)['url'] as String);
    return recorded.host == uri.host &&
        recorded.path == uri.path &&
        _sameQuery(recorded, uri);
  }, orElse: () => throw StateError('No recorded sample for GET $uri'));
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

/// [body]'s projection with the number of requests it made.
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
  return {'requests': _requests.length - before, 'value': value};
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
  'nextCursor': page.nextCursor,
  'rooms': _rooms(page.rooms),
};

Map<String, dynamic> _qualityProjection(LivePlayQuality quality) => {
  'quality': quality.quality,
  'id': quality.id,
  'sort': quality.sort,
  'data': quality.data,
};

// Samples ---------------------------------------------------------------------

/// The fixed catalog (no request), the popular directory's first page by
/// every entry 3.x had, and the second page by cursor and by replay.
Future<void> _directory() async {
  _load(['S03-lives-p1', 'S03-lives-p2']);
  final site = ChzzkSite(api: ChzzkApi(request: _replay));
  final categories = await site.getCategores(1, 30);
  final area = categories.single.children.single;
  final first = await site.getDirectoryPage(page: 1);
  _write(
    'S03-lives-p1',
    'ChzzkSite.getCategores + getDirectoryPage(1) + getRecommendRooms(1) + getCategoryRooms(1)',
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
    },
  );
  _write(
    'S03-lives-p2',
    'ChzzkSite.getDirectoryPageAtCursor(2, cursor of page 1) + getDirectoryPage(2)',
    {
      'cursor': first.nextCursor,
      'getDirectoryPageAtCursor(2)': await _outcome(
        () => site.getDirectoryPageAtCursor(page: 2, cursor: first.nextCursor),
        _pageProjection,
      ),
      'getDirectoryPage(2)': await _outcome(
        () => site.getDirectoryPage(page: 2),
        _pageProjection,
      ),
    },
  );
}

/// Search with the recorded page size (20; 3.x's default was 30, the
/// response is the same shape).
Future<void> _search(String sample, String keyword) async {
  _load([sample]);
  final site = ChzzkSite(api: ChzzkApi(request: _replay));
  _write(sample, 'ChzzkSite.searchRooms(page 1, pageSize 20)', {
    'searchRooms': await _outcome(
      () => site.searchRooms(keyword, page: 1, pageSize: 20),
      _rooms,
    ),
  });
}

Future<void> _channel(String sample, String id) async {
  _load([sample]);
  final api = ChzzkApi(request: _replay);
  _write(sample, 'ChzzkApi.channel', {
    'channel': await _outcome(
      () => api.channel(id),
      (channel) => {
        'id': channel.id,
        'name': channel.name,
        'avatar': channel.avatar,
        'description': channel.description,
        'followers': channel.followers,
        'isLive': channel.isLive,
      },
    ),
  });
}

/// Every entry 3.x had for one room: room entry, follow refresh, recording
/// detail, state, qualities with their URLs, recovery.
Future<void> _room(
  String sample,
  List<String> samples,
  String id, {
  bool channelFromLiveDetail = false,
}) async {
  _load(samples);
  if (channelFromLiveDetail) {
    final live =
        (jsonDecode(_body(sample)) as Map<String, dynamic>)['content']
            as Map<String, dynamic>;
    _synthetic['/service/v1/channels/$id'] = jsonEncode({
      'code': 200,
      'message': null,
      'content': live['channel'],
    });
  }
  final site = ChzzkSite(api: ChzzkApi(request: _replay));
  final value = <String, Object?>{
    'getRoomDetail': await _outcome(
      () => site.getRoomDetail(roomId: id, platform: 'chzzk'),
      _roomProjection,
    ),
    'getRoomDetailForRefresh': await _outcome(
      () => site.getRoomDetailForRefresh(roomId: id, platform: 'chzzk'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _outcome(
      () => site.getRoomDetailForRecording(roomId: id, platform: 'chzzk'),
      _roomProjection,
    ),
    'getLiveStatus': await _outcome(
      () => site.getLiveStatus(roomId: id, platform: 'chzzk'),
      (live) => live,
    ),
  };
  final detail = await site.getRoomDetail(roomId: id, platform: 'chzzk');
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
    value['resolvePlayUrlsForRecoveryRaw'] = {
      for (final quality in qualities)
        '${quality.id}': await _outcome(
          () => site.resolvePlayUrlsForRecoveryRaw(
            detail: detail,
            quality: quality,
          ),
          (resolution) => {
            'urls': resolution.urls,
            'appliedQualityData': resolution.appliedQualityData,
          },
        ),
    };
  } on StateError {
    rethrow;
  } on Object {
    // Recorded above as getPlayQualites.
  }
  _write(
    sample,
    'ChzzkSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
    'getPlayQualites + getPlayUrls + resolvePlayUrlsForRecoveryRaw',
    value,
  );
}

/// The live-detail of a channel that does not exist (HTTP 404). 3.x never
/// reached it for this id (the channel request fails first), so its owner is
/// given directly.
Future<void> _liveDetailMissing() async {
  _load(['S06-live-detail-notfound']);
  final api = ChzzkApi(request: _replay);
  const owner = ChzzkChannel(
    id: _missing,
    name: '(알 수 없음)',
    avatar: '',
    description: '',
    followers: 0,
    isLive: false,
  );
  _write('S06-live-detail-notfound', 'ChzzkApi.liveDetail', {
    'liveDetail': await _outcome(
      () => api.liveDetail(_missing, owner),
      (live) => live?.liveId,
    ),
  });
}

/// One master alone: 3.x's `_qualities` over a live whose only media is this
/// master.
Future<void> _master(String sample, String mediaId) async {
  _load([sample]);
  final url =
      (_meta(sample)['request'] as Map<String, dynamic>)['url'] as String;
  final site = ChzzkSite(api: ChzzkApi(request: _replay));
  final live = ChzzkLive(
    liveId: 1,
    channel: const ChzzkChannel(
      id: _live,
      name: 'fixture',
      avatar: '',
      description: '',
      followers: null,
      isLive: true,
    ),
    title: 'fixture',
    cover: '',
    category: '',
    concurrentViewers: null,
    adult: false,
    regionRestricted: false,
    isLive: true,
    timeMachineActive: false,
    media: [ChzzkMedia(id: mediaId, url: url, lowLatency: mediaId == 'LLHLS')],
  );
  _write(sample, 'ChzzkSite._qualities (this master only)', {
    'qualities': await _outcome(
      () => site._qualities(live),
      (qualities) => [
        for (final quality in qualities) _qualityProjection(quality),
      ],
    ),
  });
}

// 3.x's i18n (assets/translations/zh.json) ----------------------------------------

const Map<String, String> _zh = {
  'chzzk_directory_scope': '官方公开热门直播目录，使用包含边界项的游标分页；原生频道搜索同时返回开播和未开播频道。仅在 cvExposure 允许时展示 concurrentUserCount。',
  'chzzk_public_directory': '公开热门直播',
  'chzzk_adult_notice': '成人分级房间未返回公开匿名媒体源。',
  'chzzk_region_notice': '当前地区受到播放限制。',
  'chzzk_time_machine_notice': '实时 HLS 已启用；独立时光机回看会话纳入下一协议批次。',
};

String i18n(String key) =>
    _zh[key] ?? (throw StateError('No zh.json text for $key'));

// Dio and the request scope (only what the copied code names) -----------------

class CancelToken {
  bool get isCancelled => false;
  static bool isCancel(Object error) => false;
}

class DioException implements Exception {}

Future<T> withRequestCancellation<T>(
  CancelToken? caller,
  Future<T> Function(CancelToken transport) consume,
) => consume(CancelToken());

// 3.x models (the parts the CHZZK adapter uses) ------------------------------

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

// 3.x's hls_master_selection.dart (HlsMasterPlaylist.parse, unchanged; the
// selection and rewrite parts left out) ---------------------------------------

final class HlsMasterVariant {
  HlsMasterVariant._(this.uri, this.line, Map<String, String> attributes)
    : attributes = Map.unmodifiable(attributes);
  final Uri uri;
  final String line;
  final Map<String, String> attributes;
}

final class HlsMasterPlaylist {
  HlsMasterPlaylist._(
    this.source,
    this._prefix,
    List<HlsMasterVariant> variants,
    this._audio,
  ) : variants = List.unmodifiable(variants);
  final Uri source;
  final List<String> _prefix;
  final List<HlsMasterVariant> variants;
  final List<({Uri uri, String line, String group})> _audio;

  static HlsMasterPlaylist parse(Uri source, String text) {
    _resolve(source, source.toString());
    if (text.length > 4 * 1024 * 1024 ||
        utf8.encode(text).length > 4 * 1024 * 1024) {
      throw const FormatException('HLS master exceeds byte budget');
    }
    final lines = const LineSplitter()
        .convert(text)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty || lines.first != '#EXTM3U')
      throw const FormatException('Expected HLS master');
    final prefix = <String>['#EXTM3U'];
    final variants = <HlsMasterVariant>[];
    final audio = <({Uri uri, String line, String group})>[];
    final audioNames = <(String, String)>{};
    final audioUris = <Uri>{};
    final videoUris = <Uri>{};
    String? pending;
    var version = false;
    var independent = false;
    for (final line in lines.skip(1)) {
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        if (pending != null || variants.length >= 32)
          throw const FormatException('Invalid HLS variant count');
        pending = line;
      } else if (line.startsWith('#EXT-X-MEDIA:')) {
        if (pending != null || audio.length >= 32)
          throw const FormatException('Invalid HLS rendition placement');
        final attrs = _attributes(line.substring(13));
        if (attrs['TYPE'] != 'AUDIO' ||
            (attrs['GROUP-ID'] ?? '').isEmpty ||
            (attrs['NAME'] ?? '').isEmpty ||
            attrs.keys.any(
              (key) => !const {
                'TYPE',
                'GROUP-ID',
                'NAME',
                'URI',
                'DEFAULT',
                'AUTOSELECT',
                'LANGUAGE',
                'CHANNELS',
                'CHARACTERISTICS',
              }.contains(key),
            )) {
          throw const FormatException('Unsupported HLS rendition');
        }
        for (final key in ['DEFAULT', 'AUTOSELECT']) {
          if (attrs.containsKey(key) &&
              !const {'YES', 'NO'}.contains(attrs[key])) {
            throw const FormatException('Invalid HLS audio flags');
          }
        }
        final uri = _resolve(source, attrs['URI'] ?? '');
        if (!audioNames.add((attrs['GROUP-ID']!, attrs['NAME']!)) ||
            !audioUris.add(uri)) {
          throw const FormatException('Ambiguous HLS rendition identity');
        }
        audio.add((uri: uri, line: line, group: attrs['GROUP-ID']!));
      } else if (line.startsWith('#EXT-X-VERSION:')) {
        if (pending != null ||
            version ||
            !RegExp(r'^[1-9]\d*$').hasMatch(line.substring(15))) {
          throw const FormatException('Invalid HLS version');
        }
        version = true;
        prefix.add(line);
      } else if (line == '#EXT-X-INDEPENDENT-SEGMENTS') {
        if (pending != null || independent)
          throw const FormatException('Invalid HLS independence tag');
        independent = true;
        prefix.add(line);
      } else if (line.startsWith('#')) {
        if (line.startsWith('#EXT'))
          throw const FormatException('Unsupported HLS master tag');
      } else {
        if (pending == null) throw const FormatException('Unexpected HLS URI');
        final attrs = _attributes(pending.substring(18));
        final rate = int.tryParse(attrs['BANDWIDTH'] ?? '');
        if (rate == null ||
            rate <= 0 ||
            rate > 9007199254740991 ||
            attrs.keys.any(
              (key) => !const {
                'BANDWIDTH',
                'AVERAGE-BANDWIDTH',
                'RESOLUTION',
                'CODECS',
                'FRAME-RATE',
                'AUDIO',
                'CLOSED-CAPTIONS',
              }.contains(key),
            ) ||
            (attrs.containsKey('CLOSED-CAPTIONS') &&
                attrs['CLOSED-CAPTIONS'] != 'NONE')) {
          throw const FormatException('Unsupported HLS variant');
        }
        if (attrs.containsKey('AVERAGE-BANDWIDTH')) {
          final average = int.tryParse(attrs['AVERAGE-BANDWIDTH']!);
          if (average == null || average <= 0 || average > 9007199254740991) {
            throw const FormatException('Invalid HLS average bandwidth');
          }
        }
        if (attrs.containsKey('RESOLUTION') &&
            !RegExp(r'^[1-9]\d{0,4}x[1-9]\d{0,4}$')
                .hasMatch(attrs['RESOLUTION']!)) {
          throw const FormatException('Invalid HLS resolution');
        }
        if (attrs.containsKey('FRAME-RATE')) {
          final frames = double.tryParse(attrs['FRAME-RATE']!);
          if (frames == null ||
              !frames.isFinite ||
              frames <= 0 ||
              frames > 1000) {
            throw const FormatException('Invalid HLS frame rate');
          }
        }
        if (attrs['CODECS'] == '')
          throw const FormatException('Empty HLS codecs');
        final uri = _resolve(source, line);
        if (!videoUris.add(uri))
          throw const FormatException('Ambiguous HLS variant identity');
        variants.add(HlsMasterVariant._(uri, pending, attrs));
        pending = null;
      }
    }
    if (pending != null || variants.isEmpty)
      throw const FormatException('Incomplete HLS master');
    if (videoUris.contains(source) ||
        audioUris.contains(source) ||
        videoUris.any(audioUris.contains)) {
      throw const FormatException('Cyclic or overlapping HLS media selection');
    }
    for (final variant in variants) {
      final group = variant.attributes['AUDIO'];
      if (group != null &&
          (group.isEmpty || !audio.any((item) => item.group == group))) {
        throw const FormatException('Missing HLS audio group');
      }
    }
    return HlsMasterPlaylist._(source, prefix, variants, audio);
  }
}

Uri _resolve(Uri source, String text) {
  final uri = source.resolve(text);
  if (!const {'http', 'https'}.contains(source.scheme) ||
      source.host.isEmpty ||
      source.userInfo.isNotEmpty ||
      source.hasFragment ||
      text.isEmpty ||
      text.length > 65536 ||
      text.contains(RegExp(r'[\x00-\x20\x7f]')) ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      (source.scheme == 'https' && uri.scheme != 'https')) {
    throw const FormatException('Invalid HLS master URI');
  }
  return uri;
}

Map<String, String> _attributes(String text) {
  final values = <String, String>{};
  final pattern = RegExp(r'([A-Z0-9-]+)=("[^"\r\n\x00]*"|[^,\s"]+)(?:,|$)');
  var offset = 0;
  while (offset < text.length) {
    final match = pattern.matchAsPrefix(text, offset);
    if (match == null || values.containsKey(match[1]))
      throw const FormatException('Malformed HLS attributes');
    final value = match[2]!;
    values[match[1]!] = value.startsWith('"')
        ? value.substring(1, value.length - 1)
        : value;
    offset = match.end;
  }
  if (text.endsWith(','))
    throw const FormatException('Incomplete HLS attributes');
  return values;
}

// 3.x's chzzk_link.dart (unchanged) --------------------------------------------

class ChzzkLink {
  const ChzzkLink._();

  static String? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.host.toLowerCase() != 'chzzk.naver.com') {
      return null;
    }
    final segments = uri.pathSegments
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (segments.length != 2 || segments.first != 'live') return null;
    final id = segments[1].trim().toLowerCase();
    return RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ? id : null;
  }

  static String url(String channelId) {
    final id = channelId.trim().toLowerCase();
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id))
      throw const FormatException('Invalid CHZZK channel ID');
    return 'https://chzzk.naver.com/live/$id';
  }
}

// 3.x's chzzk_api.dart (transport injected; `_defaultRequest` and `readBody`
// left out) ---------------------------------------------------------------------

enum ChzzkFailure {
  transport,
  access,
  rateLimited,
  service,
  missing,
  schema,
  cancelled,
  identity,
  mediaUnavailable,
}

class ChzzkException implements Exception {
  const ChzzkException(this.kind);

  final ChzzkFailure kind;

  @override
  String toString() => 'CHZZK ${kind.name}';
}

typedef ChzzkRequest = Future<({int status, String body})> Function(
  Uri uri,
  CancelToken? cancel,
);

class ChzzkChannel {
  const ChzzkChannel({
    required this.id,
    required this.name,
    required this.avatar,
    required this.description,
    required this.followers,
    required this.isLive,
  });

  final String id;
  final String name;
  final String avatar;
  final String description;
  final int? followers;
  final bool isLive;
}

class ChzzkMedia {
  const ChzzkMedia({
    required this.id,
    required this.url,
    required this.lowLatency,
  });

  final String id;
  final String url;
  final bool lowLatency;
}

class ChzzkLive {
  ChzzkLive({
    required this.liveId,
    required this.channel,
    required this.title,
    required this.cover,
    required this.category,
    required this.concurrentViewers,
    required this.adult,
    required this.regionRestricted,
    required this.isLive,
    required this.timeMachineActive,
    required Iterable<ChzzkMedia> media,
  }) : media = List.unmodifiable(media);

  final int liveId;
  final ChzzkChannel channel;
  final String title;
  final String cover;
  final String category;
  final int? concurrentViewers;
  final bool adult;
  final bool regionRestricted;
  final bool isLive;
  final bool timeMachineActive;
  final List<ChzzkMedia> media;
}

class ChzzkRoom {
  const ChzzkRoom(this.channel, this.live);

  final ChzzkChannel channel;
  final ChzzkLive? live;
}

class ChzzkDirectoryPage {
  ChzzkDirectoryPage({
    required Iterable<ChzzkLive> lives,
    required this.nextCursor,
    required this.hasMore,
  }) : lives = List.unmodifiable(lives);

  final List<ChzzkLive> lives;
  final String? nextCursor;
  final bool hasMore;
}

class ChzzkApi {
  ChzzkApi({required ChzzkRequest request}) : _request = request;

  static const apiOrigin = 'https://api.chzzk.naver.com';
  static const webOrigin = 'https://chzzk.naver.com';
  static const responseLimit = 2 * 1024 * 1024;
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  static const headers = {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Origin': webOrigin,
    'Referer': '$webOrigin/',
  };
  static const mediaHeaders = {
    'User-Agent': userAgent,
    'Referer': '$webOrigin/',
  };

  final ChzzkRequest _request;

  Future<String> _read(Uri uri, CancelToken? cancel) async {
    if (cancel?.isCancelled == true)
      throw const ChzzkException(ChzzkFailure.cancelled);
    late final ({int status, String body}) response;
    try {
      response = await _request(uri, cancel);
    } on StateError {
      rethrow;
    } catch (error) {
      if (cancel?.isCancelled == true ||
          (error is DioException && CancelToken.isCancel(error))) {
        throw const ChzzkException(ChzzkFailure.cancelled);
      }
      if (error is ChzzkException) rethrow;
      throw const ChzzkException(ChzzkFailure.transport);
    }
    if (cancel?.isCancelled == true)
      throw const ChzzkException(ChzzkFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      400 => ChzzkFailure.schema,
      401 || 403 => ChzzkFailure.access,
      404 => ChzzkFailure.missing,
      429 => ChzzkFailure.rateLimited,
      >= 500 => ChzzkFailure.service,
      _ => ChzzkFailure.transport,
    };
    if (failure != null) throw ChzzkException(failure);
    if (response.body.length > responseLimit)
      throw const ChzzkException(ChzzkFailure.schema);
    return response.body;
  }

  Future<Object?> _get(
    String path,
    Map<String, String> query,
    CancelToken? cancel,
  ) async {
    final body = await _read(
      Uri.parse('$apiOrigin$path')
          .replace(queryParameters: query.isEmpty ? null : query),
      cancel,
    );
    try {
      final root = _object(jsonDecode(body));
      if (_integer(root['code']) != 200)
        throw const ChzzkException(ChzzkFailure.service);
      return root['content'];
    } on FormatException {
      throw const ChzzkException(ChzzkFailure.schema);
    }
  }

  Future<String> manifest(String url, {CancelToken? cancel}) =>
      _read(_mediaUri(url), cancel);

  Future<ChzzkDirectoryPage> directory({
    int size = 30,
    String? cursor,
    CancelToken? cancel,
  }) async {
    if (size < 1 || size > 30) throw const ChzzkException(ChzzkFailure.schema);
    final decodedCursor = cursor == null
        ? null
        : _decodeDirectoryCursor(cursor);
    final query = <String, String>{
      // The server cursor is inclusive, so one extra row preserves a full
      // logical page after removing the repeated boundary item.
      'size': '${decodedCursor == null ? size : size + 1}',
      if (decodedCursor != null) 'concurrentUserCount': '${decodedCursor.$1}',
      if (decodedCursor != null) 'liveId': '${decodedCursor.$2}',
    };
    final content = _object(await _get('/service/v1/lives', query, cancel));
    final rows = _list(
      content['data'],
      max: 64,
    ).map((value) => _live(_object(value))).toList(growable: true);
    if (decodedCursor != null &&
        rows.isNotEmpty &&
        rows.first.liveId == decodedCursor.$2)
      rows.removeAt(0);
    if (rows.length > size) rows.removeRange(size, rows.length);

    final page = content['page'];
    String? nextCursor;
    if (page is Map && page['next'] is Map) {
      final next = _object(page['next']);
      nextCursor = _encodeDirectoryCursor(
        _nonNegativeInt(next['concurrentUserCount']),
        _positiveInt(next['liveId']),
      );
    }
    if (nextCursor == cursor) nextCursor = null;
    return ChzzkDirectoryPage(
      lives: rows,
      nextCursor: nextCursor,
      hasMore: nextCursor != null && rows.isNotEmpty,
    );
  }

  Future<List<ChzzkChannel>> searchChannels(
    String keyword, {
    int offset = 0,
    int size = 30,
    CancelToken? cancel,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty ||
        query.length > 100 ||
        offset < 0 ||
        offset > 1000000 ||
        size < 1 ||
        size > 30) {
      throw const ChzzkException(ChzzkFailure.schema);
    }
    final content = _object(
      await _get('/service/v1/search/channels', {
        'keyword': query,
        'offset': '$offset',
        'size': '$size',
      }, cancel),
    );
    return _list(content['data'], max: 64)
        .map((value) => _channel(_object(_object(value)['channel'])))
        .toList(growable: false);
  }

  Future<ChzzkChannel> channel(String channelId, {CancelToken? cancel}) async {
    final id = _channelId(channelId);
    final content = await _get('/service/v1/channels/$id', const {}, cancel);
    if (content == null) throw const ChzzkException(ChzzkFailure.missing);
    final result = _channel(_object(content));
    if (result.id != id) throw const ChzzkException(ChzzkFailure.identity);
    return result;
  }

  Future<ChzzkLive?> liveDetail(
    String channelId,
    ChzzkChannel owner, {
    CancelToken? cancel,
  }) async {
    final id = _channelId(channelId);
    if (owner.id != id) throw const ChzzkException(ChzzkFailure.identity);
    // v2 now answers overseas-restricted lives with HTTP 500 / code 9004 and
    // no detail at all; v3.1 (the web player's version) returns the same
    // fields with krOnlyViewing set and no playback, which the room card
    // already presents as a region notice.
    final content = await _get(
      '/service/v3.1/channels/$id/live-detail',
      const {},
      cancel,
    );
    if (content == null) return null;
    final detail = _object(content);
    final status = _text(detail['status']);
    final liveOwner = _channel(
      _object(detail['channel']),
      description: owner.description,
      followers: owner.followers,
    );
    if (liveOwner.id != id) throw const ChzzkException(ChzzkFailure.identity);
    final isLive = status == 'OPEN';
    if (!isLive && status != 'CLOSE' && status != 'CLOSED')
      throw const ChzzkException(ChzzkFailure.schema);
    final adult = _bool(detail['adult']);
    final regionRestricted = _bool(detail['krOnlyViewing']);
    final media = isLive
        ? _playbackMedia(detail['livePlaybackJson'])
        : const <ChzzkMedia>[];
    return ChzzkLive(
      liveId: _positiveInt(detail['liveId']),
      channel: ChzzkChannel(
        id: liveOwner.id,
        name: liveOwner.name,
        avatar: liveOwner.avatar,
        description: liveOwner.description,
        followers: liveOwner.followers,
        isLive: isLive,
      ),
      title: _optionalText(detail['liveTitle'], fallback: owner.name),
      cover: _cover(detail['liveImageUrl'], detail['defaultThumbnailImageUrl']),
      category: _optionalText(
        detail['liveCategoryValue'] ?? detail['liveCategory'],
      ),
      concurrentViewers: _visibleViewers(detail),
      adult: adult,
      regionRestricted: regionRestricted,
      isLive: isLive,
      timeMachineActive: _bool(detail['timeMachineActive']),
      media: media,
    );
  }

  Future<ChzzkRoom> room(String channelId, {CancelToken? cancel}) async {
    final owner = await channel(channelId, cancel: cancel);
    final live = await liveDetail(owner.id, owner, cancel: cancel);
    return ChzzkRoom(owner, live);
  }

  static ChzzkLive _live(Map<String, dynamic> data) {
    final channel = _channel(_object(data['channel']), isLive: true);
    return ChzzkLive(
      liveId: _positiveInt(data['liveId']),
      channel: channel,
      title: _text(data['liveTitle']),
      cover: _cover(data['liveImageUrl'], data['defaultThumbnailImageUrl']),
      category: _optionalText(
        data['liveCategoryValue'] ?? data['liveCategory'],
      ),
      concurrentViewers: _visibleViewers(data),
      adult: _bool(data['adult']),
      regionRestricted: false,
      isLive: true,
      timeMachineActive: false,
      media: const [],
    );
  }

  static ChzzkChannel _channel(
    Map<String, dynamic> data, {
    String description = '',
    int? followers,
    bool? isLive,
  }) => ChzzkChannel(
    id: _channelId(data['channelId']),
    name: _text(data['channelName']),
    avatar: _image(data['channelImageUrl']),
    description: data.containsKey('channelDescription')
        ? _optionalText(data['channelDescription'])
        : description,
    followers: data.containsKey('followerCount')
        ? _optionalNonNegativeInt(data['followerCount'])
        : followers,
    isLive:
        isLive ?? (data['openLive'] is bool ? data['openLive'] as bool : false),
  );

  static List<ChzzkMedia> _playbackMedia(Object? raw) {
    if (raw == null || raw == '') return const [];
    if (raw is! String || raw.length > responseLimit)
      throw const ChzzkException(ChzzkFailure.schema);
    late final Map<String, dynamic> playback;
    try {
      playback = _object(jsonDecode(raw));
    } on FormatException {
      throw const ChzzkException(ChzzkFailure.schema);
    }
    final result = <ChzzkMedia>[];
    final seen = <String>{};
    for (final value in _list(playback['media'], max: 16)) {
      final media = _object(value);
      if (_text(media['protocol']) != 'HLS') continue;
      final mediaId = _text(media['mediaId']);
      if (mediaId != 'HLS' && mediaId != 'LLHLS') continue;
      final url = _mediaUri(_text(media['path'])).toString();
      if (seen.add(url))
        result.add(
          ChzzkMedia(id: mediaId, url: url, lowLatency: mediaId == 'LLHLS'),
        );
    }
    return List.unmodifiable(result);
  }

  static int? _visibleViewers(Map<String, dynamic> data) {
    if (data['cvExposure'] != true) return null;
    return _optionalNonNegativeInt(data['concurrentUserCount']);
  }

  static String _cover(Object? primary, Object? fallback) {
    for (final value in [primary, fallback]) {
      if (value is! String || value.isEmpty) continue;
      final expanded = value.replaceAll('{type}', '480');
      final result = _image(expanded);
      if (result.isNotEmpty) return result;
    }
    return '';
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const ChzzkException(ChzzkFailure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static List<dynamic> _list(Object? value, {required int max}) {
    if (value is! List || value.length > max)
      throw const ChzzkException(ChzzkFailure.schema);
    return value;
  }

  static int? _integer(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');

  static int _positiveInt(Object? value) {
    final parsed = _integer(value);
    if (parsed == null || parsed <= 0)
      throw const ChzzkException(ChzzkFailure.schema);
    return parsed;
  }

  static int _nonNegativeInt(Object? value) {
    final parsed = _integer(value);
    if (parsed == null || parsed < 0)
      throw const ChzzkException(ChzzkFailure.schema);
    return parsed;
  }

  static int? _optionalNonNegativeInt(Object? value) {
    if (value == null || value == '') return null;
    return _nonNegativeInt(value);
  }

  static bool _bool(Object? value) {
    if (value is! bool) throw const ChzzkException(ChzzkFailure.schema);
    return value;
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 8192) {
      throw const ChzzkException(ChzzkFailure.schema);
    }
    return value.trim();
  }

  static String _optionalText(Object? value, {String fallback = ''}) {
    if (value == null || value == '') return fallback;
    if (value is! String || value.length > 131072)
      throw const ChzzkException(ChzzkFailure.schema);
    final result = value.trim();
    return result.isEmpty ? fallback : result;
  }

  static String _channelId(Object? value) {
    final result = value?.toString().trim() ?? '';
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(result))
      throw const ChzzkException(ChzzkFailure.identity);
    return result;
  }

  static String _image(Object? value) {
    if (value is! String || value.length > 8192) return '';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment)
      return '';
    final host = uri.host.toLowerCase();
    return host == 'pstatic.net' ||
            host.endsWith('.pstatic.net') ||
            host == 'akamaized.net' ||
            host.endsWith('.akamaized.net')
        ? value
        : '';
  }

  static Uri _mediaUri(String value) {
    if (value.length > 16384 || value.contains(RegExp(r'[\s\x00-\x1f]'))) {
      throw const ChzzkException(ChzzkFailure.schema);
    }
    final uri = Uri.tryParse(value);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !(host == 'akamaized.net' || host.endsWith('.akamaized.net'))) {
      throw const ChzzkException(ChzzkFailure.schema);
    }
    return uri;
  }

  static String _encodeDirectoryCursor(int viewers, int liveId) =>
      jsonEncode({'v': viewers, 'l': liveId});

  static (int, int) _decodeDirectoryCursor(String cursor) {
    if (cursor.length > 128) throw const ChzzkException(ChzzkFailure.schema);
    try {
      final data = _object(jsonDecode(cursor));
      if (data.length != 2 ||
          !data.containsKey('v') ||
          !data.containsKey('l')) {
        throw const ChzzkException(ChzzkFailure.schema);
      }
      return (_nonNegativeInt(data['v']), _positiveInt(data['l']));
    } on FormatException {
      throw const ChzzkException(ChzzkFailure.schema);
    }
  }
}

// 3.x's chzzk_site.dart (the LiveSite interfaces and the danmaku left out;
// `platform` checks unchanged) ---------------------------------------------------

class _ChzzkPlayback {
  _ChzzkPlayback(this.channelId, Iterable<LivePlayQuality> qualities)
    : qualities = List.unmodifiable(qualities);

  final String channelId;
  final List<LivePlayQuality> qualities;
}

class _QualityBuilder {
  _QualityBuilder({required this.id, required this.label, required this.rank});

  final String id;
  final String label;
  final int rank;
  final List<String> urls = [];
}

class ChzzkSite {
  ChzzkSite({ChzzkApi? api}) : _api = api!;

  final ChzzkApi _api;

  String get id => 'chzzk';

  String get name => 'CHZZK';

  String get directoryNoticeKey => 'chzzk_directory_scope';

  static LiveRoom _liveCard(ChzzkLive live) => LiveRoom(
    platform: 'chzzk',
    roomId: live.channel.id,
    userId: live.channel.id,
    nick: live.channel.name,
    title: live.title,
    avatar: live.channel.avatar,
    cover: live.cover,
    area: live.category,
    link: ChzzkLink.url(live.channel.id),
    liveStatus: LiveStatus.live,
    onlineViewers: live.concurrentViewers?.toString(),
    audienceMetricType: AudienceMetricType.onlineViewers,
    notice: live.adult ? i18n('chzzk_adult_notice') : null,
    httpHeaders: ChzzkApi.mediaHeaders,
  );

  static LiveRoom _channelCard(ChzzkChannel channel) => LiveRoom(
    platform: 'chzzk',
    roomId: channel.id,
    userId: channel.id,
    nick: channel.name,
    title: channel.name,
    avatar: channel.avatar,
    cover: channel.avatar,
    followers: channel.followers?.toString(),
    introduction: channel.description,
    link: ChzzkLink.url(channel.id),
    liveStatus: channel.isLive ? LiveStatus.live : LiveStatus.offline,
  );

  Future<List<LiveCategory>> getCategores(int page, int pageSize) async =>
      page == 1
      ? [
          LiveCategory(
            id: id,
            name: name,
            children: [
              LiveArea(
                platform: id,
                areaType: 'directory',
                areaId: 'popular',
                areaName: i18n('chzzk_public_directory'),
                typeName: name,
              ),
            ],
          ),
        ]
      : [];

  void _validateCategory(LiveArea? category) {
    if (category != null &&
        (category.platform != id ||
            category.areaType != 'directory' ||
            category.areaId != 'popular')) {
      throw const ChzzkException(ChzzkFailure.identity);
    }
  }

  Future<LiveDirectoryPage> getDirectoryPageAtCursor({
    required int page,
    String? cursor,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    if (page < 1 ||
        (page == 1 && cursor != null) ||
        (page > 1 && cursor == null)) {
      throw const ChzzkException(ChzzkFailure.schema);
    }
    _validateCategory(category);
    final result = await _api.directory(cursor: cursor, cancel: cancel);
    final seen = <String>{};
    return LiveDirectoryPage(
      page: page,
      nextCursor: result.nextCursor,
      hasMore: result.hasMore,
      rooms: result.lives
          .where((live) => seen.add(live.channel.id))
          .map(_liveCard),
    );
  }

  Future<LiveDirectoryPage> getDirectoryPage({
    int page = 1,
    LiveArea? category,
    CancelToken? cancel,
  }) async {
    if (page < 1 || page > 20) throw const ChzzkException(ChzzkFailure.schema);
    _validateCategory(category);
    return withRequestCancellation(cancel, (owned) async {
      Future<LiveDirectoryPage> replay() async {
        String? cursor;
        for (var current = 1; current <= page; current++) {
          final result = await getDirectoryPageAtCursor(
            page: current,
            cursor: cursor,
            category: category,
            cancel: owned,
          );
          if (current == page) return result;
          if (!result.hasMore)
            return LiveDirectoryPage(
              page: page,
              hasMore: false,
              rooms: const [],
            );
          cursor = result.nextCursor;
        }
        throw const ChzzkException(ChzzkFailure.schema);
      }

      try {
        return await replay().timeout(const Duration(seconds: 20));
      } on TimeoutException {
        throw const ChzzkException(ChzzkFailure.transport);
      }
    });
  }

  Future<List<LiveRoom>> getRecommendRooms({
    int page = 1,
    int pageSize = 30,
  }) async => (await getDirectoryPage(page: page)).rooms;

  Future<List<LiveRoom>> getCategoryRooms(
    LiveArea category, {
    int page = 1,
    int pageSize = 30,
  }) async => (await getDirectoryPage(page: page, category: category)).rooms;

  Future<List<LiveRoom>> searchRooms(
    String keyword, {
    int page = 1,
    int pageSize = 30,
  }) => searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    if (page < 1 || pageSize < 1 || pageSize > 30) return [];
    final channels = await _api.searchChannels(
      keyword,
      offset: (page - 1) * pageSize,
      size: pageSize,
      cancel: cancel,
    );
    return channels.map(_channelCard).toList(growable: false);
  }

  Future<List<LivePlayQuality>> _qualities(ChzzkLive live) async {
    final builders = <String, _QualityBuilder>{};
    for (final media in live.media) {
      late final HlsMasterPlaylist master;
      try {
        master = HlsMasterPlaylist.parse(
          Uri.parse(media.url),
          await _api.manifest(media.url),
        );
      } on FormatException {
        throw const ChzzkException(ChzzkFailure.schema);
      }
      for (final variant in master.variants) {
        final resolution = variant.attributes['RESOLUTION'] ?? '';
        final height = int.tryParse(resolution.split('x').last) ?? 0;
        final fps =
            double.tryParse(variant.attributes['FRAME-RATE'] ?? '') ?? 0;
        final bandwidth =
            int.tryParse(variant.attributes['BANDWIDTH'] ?? '') ?? 0;
        if (height <= 0 || bandwidth <= 0)
          throw const ChzzkException(ChzzkFailure.schema);
        final fpsLabel = fps >= 50 ? '60' : '';
        final key = '${height}p$fpsLabel';
        final builder = builders.putIfAbsent(
          key,
          () => _QualityBuilder(
            id: key,
            label: '$key · HLS',
            rank: height * 10000000 + bandwidth,
          ),
        );
        if (!builder.urls.contains(variant.uri.toString()))
          builder.urls.add(variant.uri.toString());
      }
    }
    final qualities =
        builders.values
            .where((builder) => builder.urls.isNotEmpty)
            .map(
              (builder) => LivePlayQuality(
                id: builder.id,
                quality: builder.label,
                sort: builder.rank,
                data: List<String>.unmodifiable(builder.urls),
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => right.sort.compareTo(left.sort));
    if (qualities.isEmpty)
      throw const ChzzkException(ChzzkFailure.mediaUnavailable);
    return qualities;
  }

  Future<LiveRoom> _detail(
    String channelId,
    String platform, {
    required bool playback,
  }) async {
    if (platform.trim().toLowerCase() != id)
      throw const ChzzkException(ChzzkFailure.identity);
    final room = await _api.room(channelId);
    final live = room.live;
    if (live == null || !live.isLive) return _channelCard(room.channel);
    final qualities = playback && live.media.isNotEmpty
        ? await _qualities(live)
        : <LivePlayQuality>[];
    final detail = _liveCard(live)
      ..followers = room.channel.followers?.toString()
      ..introduction = room.channel.description;
    if (live.regionRestricted) {
      detail.notice = i18n('chzzk_region_notice');
    } else if (live.adult && live.media.isEmpty) {
      detail.notice = i18n('chzzk_adult_notice');
    } else if (live.timeMachineActive) {
      detail.notice = i18n('chzzk_time_machine_notice');
    }
    if (qualities.isNotEmpty)
      detail.data = _ChzzkPlayback(room.channel.id, qualities);
    return detail;
  }

  Future<LiveRoom> getRoomDetail({
    required String roomId,
    required String platform,
  }) => _detail(roomId, platform, playback: true);

  Future<LiveRoom> getRoomDetailForRecording({
    required String roomId,
    required String platform,
  }) => _detail(roomId, platform, playback: true);

  Future<LiveRoom> getRoomDetailForRefresh({
    required String roomId,
    required String platform,
  }) => _detail(roomId, platform, playback: false);

  Future<bool> getLiveStatus({
    required String platform,
    required String roomId,
  }) async => (await getRoomDetailForRefresh(
    roomId: roomId,
    platform: platform,
  )).isLiveNow;

  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoom detail,
  }) async {
    if (detail.platform != id)
      throw const ChzzkException(ChzzkFailure.identity);
    if (detail.isExplicitlyOfflineNow) return [];
    final data = detail.data;
    if (data is! _ChzzkPlayback ||
        data.channelId != detail.roomId ||
        data.qualities.isEmpty) {
      throw const ChzzkException(ChzzkFailure.mediaUnavailable);
    }
    return data.qualities;
  }

  Future<List<String>> getPlayUrls({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    for (final current in await getPlayQualites(detail: detail)) {
      if (current.selectionId == quality.selectionId)
        return List.unmodifiable(current.data as List<String>);
    }
    throw const ChzzkException(ChzzkFailure.mediaUnavailable);
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    final fresh = await getRoomDetail(
      roomId: detail.roomId ?? '',
      platform: id,
    );
    return LivePlayUrlResolution(
      urls: await getPlayUrls(detail: fresh, quality: quality),
      appliedQualityData: quality.selectionId,
    );
  }
}
