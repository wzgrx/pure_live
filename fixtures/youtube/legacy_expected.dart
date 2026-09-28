// Writes expected.json for the YouTube samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.23-youtube.md, "样本与 v3 的冻结输出").
//
// The archive has no YouTube expected.json (its legacy harness only covered
// five platforms, 3.x no longer builds, and the archived samples are
// InnerTube requests 3.x never sent). The S07–S12 samples were recorded for
// this module with 3.x's own requests (watch page, `player?key=` with 3.x's
// ANDROID body, HLS master, channel `/live` page). The code below is 3.x's
// YouTubeApi, YouTubeSite and YouTubeLink, copied from
// legacy/lib/core/site/youtube/ (archive/v4). 3.x already injected its
// transport (`YouTubeRequest`), so only that function is replaced: it answers
// from the samples by method, host, path, query and (for a POST) the JSON
// body, with the empty body 3.x read for any status other than 200 and the
// request URL as the final URL (no sample was redirected); a request without
// a sample throws StateError (3.x's `_send` reports it as `transport`) and is
// listed under `unmatched`.
//
// `i18n` is replaced by the Chinese text of the keys used (3.x's zh.json);
// the danmaku getter is left out. Dio's CancelToken, DioException and
// Headers, 3.x's LiveRoom, LiveArea, LivePlayQuality, LiveDirectoryPage and
// LivePlayUrlResolution are reduced to the parts these classes use. The
// network path (`_defaultRequest`, `readBody`) is left out. The output format
// is the legacy harness's (`roomProjection`, `errorProjection`,
// `{generator, value}`); every entry point also records its requests.
//
// Run from the repository root: dart run fixtures/youtube/legacy_expected.dart
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/youtube';

const _live = 'nI725iVsyoQ';
const _liveSamples = ['S07-watch-live', 'S07-player-live', 'S07-hls-live'];

/// Links for 3.x's `YouTubeLink.parse` (no requests).
const _links = [
  'https://www.youtube.com/watch?v=nI725iVsyoQ',
  'https://www.youtube.com/watch?v=nI725iVsyoQ&t=42s&si=abc',
  'http://youtube.com/watch?v=nI725iVsyoQ',
  'https://m.youtube.com/watch?v=nI725iVsyoQ',
  'https://music.youtube.com/watch?v=nI725iVsyoQ',
  'https://www.youtube.com/watch?v=nI725iVsyoQ#t=1',
  'https://www.youtube.com/watch?v=short',
  'https://www.youtube.com/watch',
  'https://youtu.be/nI725iVsyoQ',
  'https://youtu.be/nI725iVsyoQ?si=x',
  'https://youtu.be/nI725iVsyoQ/extra',
  'https://www.youtube.com/live/nI725iVsyoQ?feature=share',
  'https://www.youtube.com/LIVE/nI725iVsyoQ',
  'https://www.youtube.com/embed/nI725iVsyoQ',
  'https://www.youtube-nocookie.com/embed/nI725iVsyoQ',
  'https://www.youtube.com/v/nI725iVsyoQ',
  'https://www.youtube.com/shorts/nI725iVsyoQ',
  'https://www.youtube.com/embed/live_stream?channel=UCSJ4gkVC6NrvII8umztf0Ow',
  'https://www.youtube.com/embed/live_stream?channel=nope',
  'https://www.youtube.com/@LofiGirl',
  'https://www.youtube.com/@LofiGirl/live',
  'https://www.youtube.com/@LofiGirl/videos',
  'https://www.youtube.com/@lo',
  'https://www.youtube.com/channel/UCSJ4gkVC6NrvII8umztf0Ow',
  'https://www.youtube.com/channel/UCSJ4gkVC6NrvII8umztf0Ow/live',
  'https://www.youtube.com/channel/UCSJ4gkVC6NrvII8umztf0Ow/videos',
  'https://www.youtube.com/channel/notachannel',
  'https://www.youtube.com/c/LofiGirl',
  'https://www.youtube.com/c/LofiGirl/live',
  'https://www.youtube.com/user/ChilledCow',
  'https://www.youtube.com/results?search_query=lofi',
  'https://www.youtube.com/',
  'https://www.youtube.com/./watch?v=nI725iVsyoQ',
  'https://user@www.youtube.com/watch?v=nI725iVsyoQ',
  'https://evilyoutube.com/watch?v=nI725iVsyoQ',
  'https://youtube.com.evil.com/watch?v=nI725iVsyoQ',
  'ftp://www.youtube.com/watch?v=nI725iVsyoQ',
  'undefined',
];

/// Search keywords for 3.x's `YouTubeLink.parseOrReference` (no requests).
const _references = [
  'nI725iVsyoQ',
  ' nI725iVsyoQ ',
  '@LofiGirl',
  'LofiGirl',
  'lofi',
  'lo',
  'lofi girl',
  'hello_world',
  'https://www.youtube.com/@LofiGirl',
  '看 https://www.youtube.com/watch?v=nI725iVsyoQ 吧',
  '',
];

void main() async {
  await _liveRoom();
  await _channelLive();
  await _channelOffline();
  await _videoRoom('S09-watch-ended', ['S09-watch-ended', 'S09-player-ended'], '9njefMDxzqw');
  await _videoRoom('S10-watch-upcoming', ['S10-watch-upcoming', 'S10-player-upcoming'], '32myp8UqPOE');
  await _videoRoom('S11-watch-video', ['S11-watch-video', 'S11-player-video'], 'dQw4w9WgXcQ');
  await _videoRoom('S12-watch-missing', ['S12-watch-missing', 'S12-player-missing'], 'aaaaaaaaaaa');
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final List<Map<String, Object?>> _requests = [];
final List<String> _unmatched = [];

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _replay(List<String> samples) {
  _samples = [for (final sample in samples) _meta(sample)];
  _requests.clear();
  _unmatched.clear();
}

bool _sameQuery(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

/// 3.x's `YouTubeRequest` over the samples: 3.x read no body for a status
/// other than 200.
Future<({int status, String body, Uri finalUri})> _fixtureRequest({
  required Uri uri,
  required Map<String, String> headers,
  Object? data,
  CancelToken? cancel,
}) async {
  final method = data == null ? 'GET' : 'POST';
  _requests.add({'method': method, 'url': uri.toString(), 'headers': headers, if (data != null) 'body': data});
  for (final meta in _samples) {
    final request = meta['request'] as Map<String, dynamic>;
    final recorded = Uri.parse(request['url'] as String);
    if (request['method'] != method ||
        recorded.host != uri.host ||
        recorded.path != uri.path ||
        !_sameQuery(recorded.queryParameters, uri.queryParameters)) {
      continue;
    }
    if (data != null && jsonEncode(jsonDecode(request['body'] as String)) != jsonEncode(data)) continue;
    final status = (meta['response'] as Map)['status'] as int;
    if (status != 200) return (status: status, body: '', finalUri: uri);
    return (status: 200, body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync(), finalUri: uri);
  }
  _unmatched.add('$method $uri');
  throw StateError('No recorded sample for $method $uri');
}

YouTubeApi _api() => YouTubeApi(request: _fixtureRequest);

YouTubeSite _site() => YouTubeSite(api: _api());

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

Object? _sync<T>(T Function() body, Object? Function(T value) project) {
  try {
    return project(body());
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

Map<String, dynamic> _roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere(
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

Object? _qualities(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'quality': quality.quality, 'id': quality.id, 'sort': quality.sort, 'data': quality.data},
];

Object? _resolution(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
};

/// The stream data 3.x kept on an entered room: every stream in 3.x's order.
Object? _streams(LiveRoom room) {
  final data = room.data;
  if (data is! YouTubeRoom) return null;
  return [
    for (final stream in data.streams)
      {
        'id': stream.id,
        'label': stream.label,
        'protocol': stream.protocol,
        'codec': stream.codec,
        'height': stream.height,
        'frameRate': stream.frameRate,
        'bitrate': stream.bitrate,
        'urls': [for (final url in stream.urls) url.toString()],
      },
  ];
}

// Samples ---------------------------------------------------------------------

/// Room entry, refresh, recording and live status of [videoId], and for an
/// entered room the qualities, every quality's URLs with 3.x's lease times,
/// the confirmation, and recovery of the first quality.
Future<Map<String, Object?>> _room(String videoId) async {
  final site = _site();
  final value = <String, Object?>{
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: videoId, platform: 'youtube'), _roomProjection),
    'getRoomDetailForRefresh': await _traced(
      () => site.getRoomDetailForRefresh(roomId: videoId, platform: 'youtube'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _traced(
      () => site.getRoomDetailForRecording(roomId: videoId, platform: 'youtube'),
      _roomProjection,
    ),
    'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: videoId, platform: 'youtube'), (live) => live),
  };
  LiveRoom? detail;
  try {
    detail = await site.getRoomDetail(roomId: videoId, platform: 'youtube');
  } on Object {
    detail = null;
  }
  if (detail == null) return value;
  final room = detail;
  value['streams'] = _streams(room);
  value['getPlayQualites'] = await _traced(() => site.getPlayQualites(detail: room), _qualities);
  List<LivePlayQuality> qualities;
  try {
    qualities = await site.getPlayQualites(detail: room);
  } on Object {
    qualities = const [];
  }
  final now = DateTime.utc(2026, 9, 28, 12, 30);
  value['resolvePlayUrlsRaw'] = {
    for (final quality in qualities)
      '${quality.id}': await _traced(() => site.resolvePlayUrlsRaw(detail: room, quality: quality), (resolution) {
        return {
          ..._resolution(resolution)! as Map<String, Object?>,
          'invalidAt': [
            for (final url in resolution.urls) site.getPlayUrlInvalidAt(url, now: now)?.toUtc().toIso8601String(),
          ],
          'refreshAt': [
            for (final url in resolution.urls) site.getPlayUrlRefreshAt(url, now: now)?.toUtc().toIso8601String(),
          ],
        };
      }),
  };
  final probe = qualities.isNotEmpty ? qualities.first : LivePlayQuality(quality: 'HLS 自动 · HLS', id: 'hls:auto');
  value['resolvePlayUrlsForRecoveryRaw(${probe.id})'] = await _traced(
    () => site.resolvePlayUrlsForRecoveryRaw(detail: room, quality: probe),
    _resolution,
  );
  value['getPlayQualites (refreshed room)'] = await _traced(() async {
    final refreshed = await site.getRoomDetailForRefresh(roomId: videoId, platform: 'youtube');
    return site.getPlayQualites(detail: refreshed);
  }, _qualities);
  return value;
}

/// The live broadcast: the three depths, qualities, URLs, leases, recovery;
/// search by the video id and by video links (no channel page); the empty
/// catalog.
Future<void> _liveRoom() async {
  _replay(_liveSamples);
  final value = <String, Object?>{_live: await _room(_live)};
  final search = <String, Object?>{};
  for (final keyword in [
    _live,
    'https://www.youtube.com/watch?v=$_live',
    'https://youtu.be/$_live',
    'https://www.youtube.com/live/$_live',
  ]) {
    search[keyword] = await _traced(
      () => _site().searchRoomsCancellable(keyword, page: 1, pageSize: 20, cancel: CancelToken()),
      _rooms,
    );
  }
  search['$_live page 2'] = await _traced(() => _site().searchRooms(_live, page: 2), _rooms);
  search['$_live pageSize 0'] = await _traced(() => _site().searchRooms(_live, pageSize: 0), _rooms);
  search['blank'] = await _traced(() => _site().searchRooms('  '), _rooms);
  search['lofi girl'] = await _traced(() => _site().searchRooms('lofi girl'), _rooms);
  value['searchRooms'] = search;
  final site = _site();
  value['catalog'] = {
    'getRecommendRooms': await _traced(() => site.getRecommendRooms(), _rooms),
    'getRecommendRooms(page: 0)': await _traced(() => site.getRecommendRooms(page: 0), _rooms),
    'getDirectoryPage': await _traced(
      () => site.getDirectoryPage(),
      (page) => {'rooms': _rooms(page.rooms), 'page': page.page, 'hasMore': page.hasMore},
    ),
    'getDirectoryPage(page: 2)': await _traced(
      () => site.getDirectoryPage(page: 2),
      (page) => {'rooms': _rooms(page.rooms), 'page': page.page, 'hasMore': page.hasMore},
    ),
    'getDirectoryPage(page: 0)': await _traced(() => site.getDirectoryPage(page: 0), (page) => page.page),
    'getDirectoryPage(category)': await _traced(
      () => site.getDirectoryPage(
        category: LiveArea(platform: 'youtube', areaId: 'x'),
      ),
      (page) => page.page,
    ),
    'directoryNoticeKey': site.directoryNoticeKey,
    'id': site.id,
    'name': site.name,
  };
  value['identity'] = {
    'getRoomDetail(other platform)': await _traced(
      () => _site().getRoomDetail(roomId: _live, platform: 'twitch'),
      _roomProjection,
    ),
    'getRoomDetail(bad id)': await _traced(
      () => _site().getRoomDetail(roomId: 'short', platform: 'youtube'),
      _roomProjection,
    ),
    'getPlayQualites(card without data)': await _traced(
      () => _site().getPlayQualites(
        detail: LiveRoom(platform: 'youtube', roomId: _live, liveStatus: LiveStatus.live),
      ),
      _qualities,
    ),
    'getPlayQualites(offline card)': await _traced(
      () => _site().getPlayQualites(
        detail: LiveRoom(platform: 'youtube', roomId: _live, liveStatus: LiveStatus.offline),
      ),
      _qualities,
    ),
  };
  _write(
    'S07-watch-live',
    'YouTubeSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
        'getPlayQualites + resolvePlayUrlsRaw + getPlayUrlInvalidAt + getPlayUrlRefreshAt + '
        'resolvePlayUrlsForRecoveryRaw + searchRoomsCancellable + getRecommendRooms + getDirectoryPage '
        '(with ${_liveSamples.join(', ')})',
    value,
  );
}

/// The live channel page: 3.x's reference resolution and search by handle
/// and channel links; 3.x's link rules (no requests).
Future<void> _channelLive() async {
  final samples = ['S07-channel-live', ..._liveSamples];
  _replay(samples);
  final api = _api();
  final references = [
    '@LofiGirl',
    'LofiGirl',
    'https://www.youtube.com/@LofiGirl',
    'https://www.youtube.com/@LofiGirl/live',
  ];
  _write(
    'S07-channel-live',
    'YouTubeApi.resolveReference + YouTubeSite.searchRoomsCancellable + YouTubeLink (with ${samples.join(', ')})',
    {
      'resolveReference': {
        for (final reference in references)
          reference: await _traced(() => api.resolveReference(YouTubeLink.parseOrReference(reference)!), (id) => id),
      },
      'searchRooms': {
        for (final reference in references)
          reference: await _traced(
            () => _site().searchRoomsCancellable(reference, page: 1, pageSize: 20, cancel: CancelToken()),
            _rooms,
          ),
      },
      'YouTubeLink.parse': {
        for (final link in _links)
          link: _sync(
            () => YouTubeLink.parse(link),
            (parsed) => parsed == null ? null : {'kind': parsed.kind.name, 'id': parsed.id, 'url': parsed.url},
          ),
      },
      'YouTubeLink.parseDurableVideoId': {for (final link in _links) link: YouTubeLink.parseDurableVideoId(link)},
      'YouTubeLink.parseOrReference': {
        for (final reference in _references)
          reference: _sync(
            () => YouTubeLink.parseOrReference(reference),
            (parsed) => parsed == null ? null : {'kind': parsed.kind.name, 'id': parsed.id, 'url': parsed.url},
          ),
      },
      'YouTubeLink.videoUrl': {
        for (final id in [_live, 'short', ' $_live ']) id: _sync(() => YouTubeLink.videoUrl(id), (url) => url),
      },
      'getPlayUrlInvalidAt': {
        for (final url in [
          'https://rr1---sn-x.googlevideo.com/videoplayback?expire=1790619788&ei=x',
          'https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/1790619788/ei/x/file/index.m3u8',
          'https://manifest.googlevideo.com/api/manifest/hls_playlist/expire/0/file/index.m3u8',
          'https://manifest.googlevideo.com/api/manifest/hls_playlist/file/index.m3u8',
          'not a url %',
        ])
          url: {
            'invalidAt': _site().getPlayUrlInvalidAt(url)?.toUtc().toIso8601String(),
            'refreshAt': _site().getPlayUrlRefreshAt(url)?.toUtc().toIso8601String(),
          },
      },
    },
  );
}

/// An offline channel's `/live` page: 3.x finds no live video.
Future<void> _channelOffline() async {
  _replay(['S08-channel-offline']);
  final api = _api();
  const channel = 'https://www.youtube.com/channel/UCX6OQ3DkcsbYNE6H8uQQuVA';
  _write(
    'S08-channel-offline',
    'YouTubeApi.resolveReference + YouTubeSite.searchRoomsCancellable (with S08-channel-offline)',
    {
      'resolveReference': await _traced(() => api.resolveReference(YouTubeLink.parse(channel)!), (id) => id),
      'searchRooms': await _traced(
        () => _site().searchRoomsCancellable(channel, page: 1, pageSize: 20, cancel: CancelToken()),
        _rooms,
      ),
    },
  );
}

/// A video that is not live now (ended, upcoming, an ordinary video, or a
/// missing id): the room at every depth and the search by its id.
Future<void> _videoRoom(String sample, List<String> samples, String videoId) async {
  _replay(samples);
  final value = <String, Object?>{videoId: await _room(videoId)};
  value['searchRooms'] = await _traced(
    () => _site().searchRoomsCancellable(videoId, page: 1, pageSize: 20, cancel: CancelToken()),
    _rooms,
  );
  _write(
    sample,
    'YouTubeSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
    'getPlayQualites + searchRoomsCancellable (with ${samples.join(', ')})',
    value,
  );
}

// 3.x models and Dio (the parts the YouTube classes use) ---------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

class CancelToken {
  bool isCancelled = false;

  static bool isCancel(Object error) => false;
}

class DioException implements Exception {}

class Headers {
  static const jsonContentType = 'application/json; charset=utf-8';
}

String i18n(String key) => const {
  'youtube_chat_notice': 'YouTube Live 远端聊天尚待接入；仅在直播页返回专用并发观看字段时显示当前在线，不把累计播放量当作在线人数。',
  'youtube_quality_hls_auto': 'HLS 自动',
  'youtube_quality_dash_auto': 'DASH 自动',
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

// 3.x's YouTube adapter (legacy/lib/core/site/youtube/) ----------------------
//
// Unchanged apart from the imports, the model stubs above, the base class,
// `@override` and the danmaku getter of YouTubeSite, and the transport:
// `_defaultRequest` and `readBody` (the network path) are left out, so
// `YouTubeApi` needs its `request` and `YouTubeSite` its `api`.

enum YouTubeLinkKind { video, channel }

class YouTubeLink {
  const YouTubeLink({required this.kind, required this.id, this.channelPath = ''});

  final YouTubeLinkKind kind;
  final String id;
  final String channelPath;

  static YouTubeLink? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !_officialHost(uri.host.toLowerCase())) {
      return null;
    }
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((value) => value.isNotEmpty).toList(growable: false);
    if (segments.any((value) => value == '.' || value == '..')) return null;
    if (host == 'youtu.be') {
      if (segments.length != 1) return null;
      final id = normalizeVideoId(segments.single);
      return id == null ? null : YouTubeLink(kind: YouTubeLinkKind.video, id: id);
    }
    if (segments.length == 1 && segments.first == 'watch') {
      final id = normalizeVideoId(uri.queryParameters['v'] ?? '');
      return id == null ? null : YouTubeLink(kind: YouTubeLinkKind.video, id: id);
    }
    if (segments.length == 2 && segments.first.toLowerCase() == 'embed' && segments[1].toLowerCase() == 'live_stream') {
      final channelId = uri.queryParameters['channel'] ?? '';
      if (RegExp(r'^UC[A-Za-z0-9_-]{20,30}$').hasMatch(channelId)) {
        final path = 'channel/$channelId';
        return YouTubeLink(kind: YouTubeLinkKind.channel, id: path, channelPath: path);
      }
      return null;
    }
    if (segments.length == 2 && const {'live', 'embed', 'v'}.contains(segments.first.toLowerCase())) {
      final id = normalizeVideoId(segments[1]);
      return id == null ? null : YouTubeLink(kind: YouTubeLinkKind.video, id: id);
    }
    final channelPath = _channelPath(segments);
    if (channelPath == null) return null;
    return YouTubeLink(kind: YouTubeLinkKind.channel, id: channelPath, channelPath: channelPath);
  }

  static YouTubeLink? parseOrReference(String raw) {
    final parsed = parse(raw);
    if (parsed != null) return parsed;
    final value = raw.trim();
    final videoId = normalizeVideoId(value);
    if (videoId != null) return YouTubeLink(kind: YouTubeLinkKind.video, id: videoId);
    final handle = normalizeHandle(value);
    return handle == null ? null : YouTubeLink(kind: YouTubeLinkKind.channel, id: '@$handle', channelPath: '@$handle');
  }

  static String? parseDurableVideoId(String raw) {
    final parsed = parse(raw);
    return parsed?.kind == YouTubeLinkKind.video ? parsed!.id : null;
  }

  static String? normalizeVideoId(String raw) {
    final value = raw.trim();
    return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(value) ? value : null;
  }

  static String? normalizeHandle(String raw) {
    final value = raw.trim().startsWith('@') ? raw.trim().substring(1) : raw.trim();
    if (value.length < 3 || value.length > 30) return null;
    return RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value) ? value : null;
  }

  static String videoUrl(String rawVideoId) {
    final videoId = normalizeVideoId(rawVideoId);
    if (videoId == null) throw const FormatException('Invalid YouTube video ID');
    return 'https://www.youtube.com/watch?v=$videoId';
  }

  String get url => switch (kind) {
    YouTubeLinkKind.video => videoUrl(id),
    YouTubeLinkKind.channel => 'https://www.youtube.com/$channelPath/live',
  };

  static String? _channelPath(List<String> segments) {
    if (segments.isEmpty || segments.length > 3) return null;
    final values = [...segments];
    if (values.last.toLowerCase() == 'live') values.removeLast();
    if (values.length == 1 && values.single.startsWith('@')) {
      final handle = normalizeHandle(values.single);
      return handle == null ? null : '@$handle';
    }
    if (values.length != 2) return null;
    final prefix = values.first.toLowerCase();
    final id = values[1];
    if (prefix == 'channel' && RegExp(r'^UC[A-Za-z0-9_-]{20,30}$').hasMatch(id)) return 'channel/$id';
    if (const {'c', 'user'}.contains(prefix) && RegExp(r'^[A-Za-z0-9_.-]{1,100}$').hasMatch(id)) {
      return '$prefix/$id';
    }
    return null;
  }

  static bool _officialHost(String host) =>
      host == 'youtu.be' ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com');
}

enum YouTubeFailure {
  transport,
  access,
  rateLimited,
  service,
  missing,
  notLive,
  schema,
  cancelled,
  identity,
  unknownState,
  mediaUnavailable,
}

class YouTubeException implements Exception {
  const YouTubeException(this.kind);

  final YouTubeFailure kind;

  @override
  String toString() => 'YouTube ${kind.name}';
}

enum YouTubeState { live, offline, restricted, unknown }

class YouTubeStream {
  const YouTubeStream({
    required this.id,
    required this.label,
    required this.protocol,
    required this.codec,
    required this.height,
    required this.frameRate,
    required this.bitrate,
    required this.urls,
  });

  final String id;
  final String label;
  final String protocol;
  final String codec;
  final int? height;
  final double? frameRate;
  final int? bitrate;
  final List<Uri> urls;
}

class YouTubeRoom {
  const YouTubeRoom({
    required this.videoId,
    required this.channelId,
    required this.author,
    required this.title,
    required this.description,
    required this.thumbnail,
    required this.category,
    required this.currentViewers,
    required this.state,
    required this.streams,
  });

  final String videoId;
  final String channelId;
  final String author;
  final String title;
  final String description;
  final String thumbnail;
  final String category;
  final int? currentViewers;
  final YouTubeState state;
  final List<YouTubeStream> streams;
}

typedef YouTubeRequest = Future<({int status, String body, Uri finalUri})> Function({
  required Uri uri,
  required Map<String, String> headers,
  Object? data,
  CancelToken? cancel,
});

class YouTubeApi {
  YouTubeApi({required YouTubeRequest request}) : _request = request;

  static const origin = 'https://www.youtube.com';
  static const responseLimit = 16 * 1024 * 1024;
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';
  static const _fallbackApiKey = 'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';

  final YouTubeRequest _request;

  static Map<String, String> pageHeaders(String videoId) => {
    'User-Agent': userAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Cookie': 'SOCS=CAI',
    'Referer': videoId.isEmpty ? '$origin/' : YouTubeLink.videoUrl(videoId),
  };

  static Map<String, String> mediaHeaders(String videoId) => {
    'User-Agent': userAgent,
    'Referer': YouTubeLink.videoUrl(videoId),
    'Origin': origin,
  };

  Future<String> resolveReference(YouTubeLink reference, {CancelToken? cancel}) async {
    if (reference.kind == YouTubeLinkKind.video) return reference.id;
    final response = await _send(Uri.parse(reference.url), headers: pageHeaders(''), cancel: cancel);
    final redirected = YouTubeLink.parse(response.finalUri.toString());
    if (redirected?.kind == YouTubeLinkKind.video) return redirected!.id;
    final canonical = RegExp(
      r'''<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(response.body);
    final canonicalLink = canonical == null ? null : YouTubeLink.parse(canonical.group(1)!);
    if (canonicalLink?.kind == YouTubeLinkKind.video) return canonicalLink!.id;
    final initialPlayer = _embeddedObject(response.body, 'ytInitialPlayerResponse');
    final playerDetails = _optionalObject(initialPlayer['videoDetails']);
    final playerId = YouTubeLink.normalizeVideoId(_text(playerDetails['videoId']));
    final playerLive = _bool(playerDetails['isLive']) == true;
    if (playerId != null && playerLive) return playerId;
    final initialData = _embeddedObject(response.body, 'ytInitialData');
    final liveId = _findLiveVideoId(initialData);
    if (liveId != null) return liveId;
    throw const YouTubeException(YouTubeFailure.notLive);
  }

  Future<YouTubeRoom> room(String rawVideoId, {required bool includeMedia, CancelToken? cancel}) async {
    final videoId = YouTubeLink.normalizeVideoId(rawVideoId);
    if (videoId == null) throw const YouTubeException(YouTubeFailure.identity);
    final page = await _send(Uri.parse(YouTubeLink.videoUrl(videoId)), headers: pageHeaders(videoId), cancel: cancel);
    final initialPlayer = _embeddedObject(page.body, 'ytInitialPlayerResponse');
    final initialData = _embeddedObject(page.body, 'ytInitialData');
    final apiKey = RegExp(r'"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"').firstMatch(page.body)?.group(1) ?? _fallbackApiKey;
    final api = await _json(
      Uri.parse('$origin/youtubei/v1/player').replace(queryParameters: {'key': apiKey}),
      headers: {
        ...pageHeaders(videoId),
        'Accept': 'application/json',
        'Content-Type': Headers.jsonContentType,
        'Origin': origin,
      },
      data: {
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
        'context': {
          'client': {
            'clientName': 'ANDROID',
            'clientVersion': '21.08.266',
            'platform': 'DESKTOP',
            'clientScreen': 'EMBED',
            'clientFormFactor': 'UNKNOWN_FORM_FACTOR',
            'browserName': 'Chrome',
          },
          'user': {'lockedSafetyMode': false},
          'request': {'useSsl': true},
        },
      },
      cancel: cancel,
    );
    final apiDetails = _optionalObject(api['videoDetails']);
    final initialDetails = _optionalObject(initialPlayer['videoDetails']);
    final details = <String, dynamic>{...initialDetails, ...apiDetails};
    final actualId = YouTubeLink.normalizeVideoId(_text(details['videoId']));
    if (actualId != videoId) throw const YouTubeException(YouTubeFailure.identity);
    final apiStatus = _optionalObject(api['playabilityStatus']);
    final initialStatus = _optionalObject(initialPlayer['playabilityStatus']);
    final status = _text(apiStatus['status']).isNotEmpty ? apiStatus : initialStatus;
    final statusCode = _text(status['status']).toUpperCase();
    final reason = _text(status['reason']).toLowerCase();
    final initialMicro = _optionalObject(_optionalObject(initialPlayer['microformat'])['playerMicroformatRenderer']);
    final apiMicro = _optionalObject(_optionalObject(api['microformat'])['playerMicroformatRenderer']);
    final micro = <String, dynamic>{...initialMicro, ...apiMicro};
    final liveDetails = _optionalObject(micro['liveBroadcastDetails']);
    final isLive = _bool(details['isLive']) == true || _bool(liveDetails['isLiveNow']) == true;
    final isLiveContent =
        isLive ||
        _bool(details['isLiveContent']) == true ||
        _bool(details['isUpcoming']) == true ||
        liveDetails.isNotEmpty;
    final isPrivate = _bool(details['isPrivate']) == true;
    final restricted =
        isPrivate ||
        const {'LOGIN_REQUIRED', 'AGE_CHECK_REQUIRED', 'CONTENT_CHECK_REQUIRED'}.contains(statusCode) ||
        reason.contains('sign in') ||
        reason.contains('private');
    final state = restricted
        ? YouTubeState.restricted
        : isLive && statusCode == 'OK'
        ? YouTubeState.live
        : isLiveContent || statusCode == 'LIVE_STREAM_OFFLINE'
        ? YouTubeState.offline
        : statusCode.isEmpty
        ? YouTubeState.unknown
        : throw const YouTubeException(YouTubeFailure.notLive);
    final title = _requiredText(details['title']);
    final author = _requiredText(details['author']);
    final thumbnail = _thumbnail(details['thumbnail'] ?? micro['thumbnail']);
    final streaming = _optionalObject(api['streamingData']);
    final streams = state == YouTubeState.live && includeMedia
        ? await _streams(streaming, videoId: videoId, cancel: cancel)
        : const <YouTubeStream>[];
    return YouTubeRoom(
      videoId: videoId,
      channelId: _text(details['channelId']),
      author: author,
      title: title,
      description: _text(details['shortDescription']),
      thumbnail: thumbnail,
      category: _text(micro['category']),
      currentViewers: state == YouTubeState.live ? _currentViewers(initialData) : null,
      state: state,
      streams: streams,
    );
  }

  Future<List<YouTubeStream>> _streams(
    Map<String, dynamic> streaming, {
    required String videoId,
    CancelToken? cancel,
  }) async {
    final result = <YouTubeStream>[];
    final seen = <String>{};
    final hlsRaw = _text(streaming['hlsManifestUrl']);
    if (hlsRaw.isNotEmpty) {
      final master = _mediaUri(hlsRaw);
      try {
        final response = await _send(master, headers: mediaHeaders(videoId), cancel: cancel);
        for (final variant in _hlsVariants(master, response.body)) {
          if (!seen.add(variant.id)) continue;
          result.add(variant);
        }
      } on YouTubeException catch (error) {
        if (error.kind == YouTubeFailure.cancelled) rethrow;
      } on FormatException {
        // Keep the master as a playable automatic source when variant metadata
        // grows beyond this adapter's bounded parser.
      }
      if (!result.any((value) => value.protocol == 'hls')) {
        result.add(
          YouTubeStream(
            id: 'hls:auto',
            label: 'HLS Auto',
            protocol: 'hls',
            codec: '',
            height: null,
            frameRate: null,
            bitrate: null,
            urls: List.unmodifiable([master]),
          ),
        );
        seen.add('hls:auto');
      }
    }
    final formats = streaming['formats'];
    if (formats is List && formats.length <= 64) {
      for (final raw in formats) {
        final format = _optionalObject(raw);
        final url = _text(format['url']);
        final itag = _int(format['itag']);
        final label = _text(format['qualityLabel']);
        if (url.isEmpty || itag == null || label.isEmpty) continue;
        final id = 'http:$itag';
        if (!seen.add(id)) continue;
        final mime = _text(format['mimeType']);
        result.add(
          YouTubeStream(
            id: id,
            label: label,
            protocol: 'http',
            codec: _codec(mime),
            height: _int(format['height']),
            frameRate: _double(format['fps']),
            bitrate: _int(format['bitrate']),
            urls: List.unmodifiable([_mediaUri(url)]),
          ),
        );
      }
    }
    final dashRaw = _text(streaming['dashManifestUrl']);
    if (dashRaw.isNotEmpty && seen.add('dash:auto')) {
      result.add(
        YouTubeStream(
          id: 'dash:auto',
          label: 'DASH Auto',
          protocol: 'dash',
          codec: '',
          height: null,
          frameRate: null,
          bitrate: null,
          urls: List.unmodifiable([_mediaUri(dashRaw)]),
        ),
      );
    }
    result.sort((left, right) {
      final rank = qualitySort(right).compareTo(qualitySort(left));
      return rank != 0 ? rank : left.id.compareTo(right.id);
    });
    return List.unmodifiable(result);
  }

  static List<YouTubeStream> _hlsVariants(Uri source, String text) {
    if (text.length > 4 * 1024 * 1024 || utf8.encode(text).length > 4 * 1024 * 1024) {
      throw const FormatException('YouTube HLS master exceeds byte budget');
    }
    final lines = const LineSplitter().convert(text).map((line) => line.trim()).where((line) => line.isNotEmpty);
    final iterator = lines.iterator;
    if (!iterator.moveNext() || iterator.current != '#EXTM3U') {
      throw const FormatException('Expected YouTube HLS master');
    }
    Map<String, String>? pending;
    final result = <YouTubeStream>[];
    final seen = <String>{};
    while (iterator.moveNext()) {
      final line = iterator.current;
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        if (pending != null || result.length >= 64) throw const FormatException('Invalid YouTube HLS variant count');
        pending = _attributes(line.substring(18));
        continue;
      }
      if (line.startsWith('#')) continue;
      if (pending == null) continue;
      final resolution = RegExp(r'^[1-9][0-9]{0,4}x([1-9][0-9]{0,4})$').firstMatch(pending['RESOLUTION'] ?? '');
      final height = int.tryParse(resolution?.group(1) ?? '');
      final frameRate = double.tryParse(pending['FRAME-RATE'] ?? '');
      final bandwidth = int.tryParse(pending['BANDWIDTH'] ?? '');
      final codec = _codec(pending['CODECS'] ?? '');
      final frameId = frameRate != null && frameRate > 30 ? frameRate.round().toString() : '0';
      final id = 'hls:${height ?? 0}:$frameId:${codec.isEmpty ? 'auto' : codec}';
      final uri = _mediaUri(source.resolve(line).toString());
      if (!seen.add(id)) throw const FormatException('Ambiguous YouTube HLS quality identity');
      result.add(
        YouTubeStream(
          id: id,
          label: height == null ? 'HLS Auto' : '${height}p${frameId == '0' ? '' : frameId}',
          protocol: 'hls',
          codec: codec,
          height: height,
          frameRate: frameRate,
          bitrate: bandwidth,
          urls: List.unmodifiable([uri]),
        ),
      );
      pending = null;
    }
    if (pending != null || result.isEmpty) throw const FormatException('Incomplete YouTube HLS master');
    return List.unmodifiable(result);
  }

  static int qualitySort(YouTubeStream stream) {
    final height = stream.height ?? 0;
    final fps = (stream.frameRate ?? 0).round().clamp(0, 999).toInt();
    final protocol = switch (stream.protocol) {
      'hls' => 30,
      'http' => 20,
      'dash' => 10,
      _ => 0,
    };
    return height * 1000 + fps + protocol;
  }

  Future<({int status, String body, Uri finalUri})> _send(
    Uri uri, {
    required Map<String, String> headers,
    Object? data,
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled == true) throw const YouTubeException(YouTubeFailure.cancelled);
    late final ({int status, String body, Uri finalUri}) response;
    try {
      response = await _request(uri: uri, headers: headers, data: data, cancel: cancel);
    } catch (error) {
      if (cancel?.isCancelled == true || (error is DioException && CancelToken.isCancel(error))) {
        throw const YouTubeException(YouTubeFailure.cancelled);
      }
      if (error is YouTubeException) rethrow;
      throw const YouTubeException(YouTubeFailure.transport);
    }
    if (cancel?.isCancelled == true) throw const YouTubeException(YouTubeFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      400 => YouTubeFailure.schema,
      401 || 403 => YouTubeFailure.access,
      404 => YouTubeFailure.missing,
      429 => YouTubeFailure.rateLimited,
      >= 500 => YouTubeFailure.service,
      _ => YouTubeFailure.transport,
    };
    if (failure != null) throw YouTubeException(failure);
    if (response.body.isEmpty || response.body.length > responseLimit) {
      throw const YouTubeException(YouTubeFailure.schema);
    }
    return response;
  }

  Future<Map<String, dynamic>> _json(
    Uri uri, {
    required Map<String, String> headers,
    required Object data,
    CancelToken? cancel,
  }) async {
    final response = await _send(uri, headers: headers, data: data, cancel: cancel);
    try {
      return _object(jsonDecode(response.body));
    } on FormatException {
      throw const YouTubeException(YouTubeFailure.schema);
    }
  }

  static Map<String, dynamic> _embeddedObject(String text, String marker) {
    var offset = text.indexOf(marker);
    while (offset >= 0) {
      final start = text.indexOf('{', offset + marker.length);
      if (start < 0) break;
      var depth = 0;
      var quoted = false;
      var escaped = false;
      for (var index = start; index < text.length; index++) {
        final code = text.codeUnitAt(index);
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
        } else if (code == 0x7d && --depth == 0) {
          try {
            return _object(jsonDecode(text.substring(start, index + 1)));
          } on FormatException {
            break;
          }
        }
      }
      offset = text.indexOf(marker, offset + marker.length);
    }
    return <String, dynamic>{};
  }

  static String? _findLiveVideoId(Object? root) {
    var visited = 0;
    String? walk(Object? value) {
      if (++visited > 250000) throw const YouTubeException(YouTubeFailure.schema);
      if (value is List) {
        for (final item in value) {
          final match = walk(item);
          if (match != null) return match;
        }
      } else if (value is Map) {
        final map = value.map((key, value) => MapEntry(key.toString(), value));
        final id = YouTubeLink.normalizeVideoId(_text(map['videoId']));
        if (id != null && _looksLive(map)) return id;
        for (final item in map.values) {
          final match = walk(item);
          if (match != null) return match;
        }
      }
      return null;
    }

    return walk(root);
  }

  static bool _looksLive(Map<String, dynamic> map) {
    if (_bool(map['isLive']) == true || _bool(map['isLiveNow']) == true) return true;
    final encoded = jsonEncode(map).toLowerCase();
    return encoded.contains('badge_style_type_live_now') ||
        encoded.contains('thumbnail_overlay_time_status_style_live') ||
        encoded.contains('"label":"live"');
  }

  static int? _currentViewers(Object? root) {
    var visited = 0;
    int? walk(Object? value) {
      if (++visited > 250000) return null;
      if (value is List) {
        for (final item in value) {
          final match = walk(item);
          if (match != null) return match;
        }
      } else if (value is Map) {
        final map = value.map((key, value) => MapEntry(key.toString(), value));
        final renderer = _optionalObject(map['videoViewCountRenderer']);
        if (renderer.isNotEmpty && _bool(renderer['isLive']) == true) {
          final text = _runsText(renderer['viewCount']);
          final number = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), ''));
          if (number != null && number >= 0) return number;
        }
        for (final item in map.values) {
          final match = walk(item);
          if (match != null) return match;
        }
      }
      return null;
    }

    return walk(root);
  }

  static String _runsText(Object? value) {
    final map = _optionalObject(value);
    final simple = _text(map['simpleText']);
    if (simple.isNotEmpty) return simple;
    final runs = map['runs'];
    if (runs is! List) return '';
    return runs.map((run) => _text(_optionalObject(run)['text'])).join();
  }

  static String _thumbnail(Object? value) {
    final items = _optionalObject(value)['thumbnails'];
    if (items is! List || items.length > 64) return '';
    for (final item in items.reversed) {
      final raw = _text(_optionalObject(item)['url']);
      if (raw.isEmpty) continue;
      final uri = Uri.tryParse(raw);
      final host = uri?.host.toLowerCase() ?? '';
      if (uri != null && uri.scheme == 'https' && uri.userInfo.isEmpty && !uri.hasFragment && _imageHost(host)) {
        return uri.toString();
      }
    }
    return '';
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const YouTubeException(YouTubeFailure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static Map<String, dynamic> _optionalObject(Object? value) {
    if (value == null) return <String, dynamic>{};
    return _object(value);
  }

  static String _requiredText(Object? value) {
    final text = _text(value);
    if (text.isEmpty || text.length > 8192) throw const YouTubeException(YouTubeFailure.schema);
    return text;
  }

  static String _text(Object? value) {
    if (value == null) return '';
    if (value is! String || value.length > 4 * 1024 * 1024) {
      throw const YouTubeException(YouTubeFailure.schema);
    }
    return value.trim();
  }

  static bool? _bool(Object? value) {
    if (value == null) return null;
    if (value is! bool) throw const YouTubeException(YouTubeFailure.schema);
    return value;
  }

  static int? _int(Object? value) {
    if (value == null || value == '') return null;
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _double(Object? value) {
    if (value == null || value == '') return null;
    final result = value is num ? value.toDouble() : double.tryParse(value.toString());
    return result != null && result.isFinite && result >= 0 ? result : null;
  }

  static String _codec(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('av01')) return 'av1';
    if (lower.contains('vp09') || lower.contains('vp9')) return 'vp9';
    if (lower.contains('hev1') || lower.contains('hvc1')) return 'h265';
    if (lower.contains('avc1') || lower.contains('h264')) return 'h264';
    return '';
  }

  static Uri _mediaUri(String raw) {
    if (raw.isEmpty || raw.length > 65536 || raw.contains(RegExp(r'[\s\x00-\x1f]'))) {
      throw const YouTubeException(YouTubeFailure.schema);
    }
    final uri = Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment || !_mediaHost(host)) {
      throw const YouTubeException(YouTubeFailure.schema);
    }
    return uri;
  }

  static bool _mediaHost(String host) =>
      host == 'googlevideo.com' ||
      host.endsWith('.googlevideo.com') ||
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtube-nocookie.com' ||
      host.endsWith('.youtube-nocookie.com');

  static bool _imageHost(String host) =>
      host == 'ytimg.com' || host.endsWith('.ytimg.com') || host == 'ggpht.com' || host.endsWith('.ggpht.com');

  static Map<String, String> _attributes(String text) {
    final values = <String, String>{};
    final pattern = RegExp(r'([A-Z0-9-]+)=("[^"\r\n\x00]*"|[^,\s"]+)(?:,|$)');
    var offset = 0;
    while (offset < text.length) {
      final match = pattern.matchAsPrefix(text, offset);
      if (match == null || values.containsKey(match[1])) {
        throw const FormatException('Malformed YouTube HLS attributes');
      }
      final value = match[2]!;
      values[match[1]!] = value.startsWith('"') ? value.substring(1, value.length - 1) : value;
      offset = match.end;
    }
    return values;
  }
}

class YouTubeSite {
  YouTubeSite({required YouTubeApi api}) : _api = api;

  final YouTubeApi _api;

  String get id => 'youtube';

  String get name => 'YouTube Live';

  String get directoryNoticeKey => 'youtube_directory_scope';

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1 || category != null) throw const YouTubeException(YouTubeFailure.schema);
    return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return [];
    return const [];
  }

  LiveRoom _card(YouTubeRoom room, {required bool includeMedia}) {
    final current = room.currentViewers?.toString();
    return LiveRoom(
      platform: id,
      roomId: room.videoId,
      userId: room.channelId,
      nick: room.author,
      title: room.title,
      avatar: room.thumbnail,
      cover: room.thumbnail,
      area: room.category.isEmpty ? 'YouTube Live' : room.category,
      introduction: room.description,
      link: YouTubeLink.videoUrl(room.videoId),
      liveStatus: switch (room.state) {
        YouTubeState.live => LiveStatus.live,
        YouTubeState.offline => LiveStatus.offline,
        YouTubeState.restricted => LiveStatus.banned,
        YouTubeState.unknown => LiveStatus.unknown,
      },
      watching: current ?? '',
      onlineViewers: current,
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: i18n('youtube_chat_notice'),
      httpHeaders: YouTubeApi.mediaHeaders(room.videoId),
      data: includeMedia ? room : null,
    );
  }

  String _videoId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const YouTubeException(YouTubeFailure.identity);
    final normalized = YouTubeLink.normalizeVideoId(roomId);
    if (normalized == null) throw const YouTubeException(YouTubeFailure.identity);
    return normalized;
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia}) async {
    final data = await _api.room(_videoId(roomId, platform), includeMedia: includeMedia);
    if (includeMedia && data.state == YouTubeState.live && data.streams.isEmpty) {
      throw const YouTubeException(YouTubeFailure.mediaUnavailable);
    }
    return _card(data, includeMedia: includeMedia);
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
      throw const YouTubeException(YouTubeFailure.unknownState);
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
    if (page != 1 || pageSize < 1) return [];
    final reference = YouTubeLink.parseOrReference(keyword);
    if (reference == null) return [];
    try {
      final videoId = await _api.resolveReference(reference, cancel: cancel);
      return [_card(await _api.room(videoId, includeMedia: false, cancel: cancel), includeMedia: false)];
    } on YouTubeException catch (error) {
      if (error.kind == YouTubeFailure.missing || error.kind == YouTubeFailure.notLive) return [];
      rethrow;
    }
  }

  YouTubeRoom _snapshot(LiveRoom detail) {
    final roomId = _videoId(detail.roomId ?? '', detail.platform ?? '');
    final data = detail.data;
    if (data is! YouTubeRoom || data.videoId != roomId || data.channelId != detail.userId) {
      throw const YouTubeException(YouTubeFailure.identity);
    }
    if (data.state == YouTubeState.unknown) throw const YouTubeException(YouTubeFailure.unknownState);
    if (data.state != YouTubeState.live || detail.isExplicitlyOfflineNow || data.streams.isEmpty) {
      throw const YouTubeException(YouTubeFailure.mediaUnavailable);
    }
    return data;
  }

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.isExplicitlyOfflineNow) return [];
    final room = _snapshot(detail);
    return List.unmodifiable(
      room.streams.map((stream) {
        final codec = stream.codec.isEmpty ? '' : ' · ${stream.codec.toUpperCase()}';
        final label = switch (stream.id) {
          'hls:auto' => i18n('youtube_quality_hls_auto'),
          'dash:auto' => i18n('youtube_quality_dash_auto'),
          _ => stream.label,
        };
        return LivePlayQuality(
          id: stream.id,
          quality: '$label$codec · ${stream.protocol.toUpperCase()}',
          sort: YouTubeApi.qualitySort(stream),
        );
      }),
    );
  }

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality, {required bool refresh}) async {
    var room = _snapshot(detail);
    if (refresh) room = _snapshot(await getRoomDetail(roomId: room.videoId, platform: id));
    final qualityId = quality.selectionId.toString();
    for (final stream in room.streams) {
      if (stream.id == qualityId) {
        return LivePlayUrlResolution(
          urls: List.unmodifiable(stream.urls.map((uri) => uri.toString())),
          appliedQualityData: qualityId,
        );
      }
    }
    throw const YouTubeException(YouTubeFailure.mediaUnavailable);
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) =>
      _resolve(detail, quality, refresh: false);

  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality, refresh: true);

  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await _resolve(detail, quality, refresh: false)).urls;

  DateTime? getPlayUrlInvalidAt(String url, {DateTime? now}) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final query = int.tryParse(uri.queryParameters['expire'] ?? '');
    if (query != null && query > 0) return DateTime.fromMillisecondsSinceEpoch(query * 1000, isUtc: true);
    final segments = uri.pathSegments;
    final index = segments.indexOf('expire');
    if (index >= 0 && index + 1 < segments.length) {
      final path = int.tryParse(segments[index + 1]);
      if (path != null && path > 0) return DateTime.fromMillisecondsSinceEpoch(path * 1000, isUtc: true);
    }
    return null;
  }

  DateTime? getPlayUrlRefreshAt(String url, {DateTime? now}) {
    final invalid = getPlayUrlInvalidAt(url, now: now);
    return invalid?.subtract(const Duration(minutes: 10));
  }
}
