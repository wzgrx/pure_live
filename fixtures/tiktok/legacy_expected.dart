// Writes expected.json for the TikTok samples: 3.x's parsers run over the
// recorded responses (docs/modules/M4.22-tiktok.md, "样本与 v3 的冻结输出").
//
// The archive has no TikTok expected.json (its legacy harness only covered
// five platforms, and 3.x no longer builds). The code below is 3.x's
// TikTokApi, TikTokLink and TikTokSite, copied from
// legacy/lib/core/site/tiktok/tiktok_api.dart, tiktok_link.dart and
// tiktok_site.dart (archive/v4), 3.x's HttpHeaderPolicy.normalize
// (legacy/lib/core/common/http_header_policy.dart, which 3.x's LiveRoom
// applied to `httpHeaders`), and the TikTok steps of
// LiveUrlTool._parseLiveUrl (legacy/lib/common/utils/live_url_tool.dart:229-234)
// and WebSearchRoomParser.parse (legacy/lib/modules/search/
// web_search_room_parser.dart:98-99).
//
// 3.x already injected its transport (`TikTokRequest`), so only that
// function is replaced: it answers from the samples by host, path and query,
// like the legacy FixtureAdapter, with the empty body 3.x read for any status
// other than 200. A request without a sample is recorded and fails the run;
// `_json` rethrows its StateError (the one harness change inside 3.x's code),
// so a harness miss is never recorded as 3.x's transport failure. The
// network-only `_defaultRequest` and `readBody` are left out, so the
// injection point is required. `i18n` is replaced by the Chinese text (3.x's
// zh.json) of the keys used; `extends LiveSite implements …`, the `@override`
// marks and the danmaku getter are left out. Dio's CancelToken and
// DioException, 3.x's LiveRoom, LiveArea, LivePlayQuality,
// LivePlayUrlResolution and LiveDirectoryPage are reduced to the parts these
// classes use (constructor defaults, the mutable fields, the state getters,
// selectionId, toJson; 3.x's toJson wrote the raw `isRecord` field and the
// normalized `httpHeaders`).
//
// 3.x trusted media and image hosts under tiktokcdn.com, tiktokv.com and
// byteoversea.com only. The live sample was served from tiktokcdn-us.com, so
// 3.x refused its streams (`schema`) and dropped its pictures. To freeze
// what 3.x made of a stream and pictures it accepted, S01-user-live and
// S01-user-offline also record every call over the same answer with
// `tiktokcdn-us.com` spelled `tiktokcdn.com` (key `trustedHosts`, nothing
// else changed).
//
// The output format is the legacy harness's (`roomProjection`,
// `errorProjection`, `{generator, value}`); every call also records the
// requests it sent.
//
// Run from the repository root: dart run fixtures/tiktok/legacy_expected.dart
// ignore_for_file: type=lint
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _root = 'fixtures/tiktok';

/// The share link of S02-room-live's broadcast (@qvc).
const _shareRoomId = '7690279124098681614';

void main() async {
  await _user('S01-user-live', 'qvc');
  await _user('S01-user-offline', 'cnn');
  await _user('S01-user-missing', 'nasa');
  await _share();
  if (_misses.isNotEmpty) {
    stderr.writeln('requests without a sample:\n${_misses.join('\n')}');
    exitCode = 1;
  }
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
String Function(String body) _rewrite = _asRecorded;
final List<Uri> _requests = [];
final List<String> _misses = [];

String _asRecorded(String body) => body;

String _trustedHosts(String body) => body.replaceAll('tiktokcdn-us.com', 'tiktokcdn.com');

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _replay(List<String> samples, {String Function(String body) rewrite = _asRecorded}) {
  _samples = [for (final sample in samples) _meta(sample)];
  _rewrite = rewrite;
  _requests.clear();
}

bool _sameQuery(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

/// 3.x's `TikTokRequest` over the samples: 3.x read no body for a status
/// other than 200.
Future<({int status, String body})> _fixtureRequest({
  required Uri uri,
  required Map<String, String> headers,
  CancelToken? cancel,
}) async {
  _requests.add(uri);
  for (final meta in _samples) {
    final request = meta['request'] as Map;
    final recorded = Uri.parse(request['url'] as String);
    if (request['method'] == 'GET' &&
        recorded.host == uri.host &&
        recorded.path == uri.path &&
        _sameQuery(recorded.queryParameters, uri.queryParameters)) {
      final status = (meta['response'] as Map)['status'] as int;
      if (status != 200) return (status: status, body: '');
      return (status: 200, body: _rewrite(File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync()));
    }
  }
  _misses.add('GET $uri');
  throw StateError('No recorded sample for GET $uri');
}

TikTokApi _api() => TikTokApi(request: _fixtureRequest);

TikTokSite _site() => TikTokSite(api: _api());

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
  json.removeWhere(
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
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

/// Inputs of the link and search rules, run with every user sample.
List<String> _inputs(String user) => [
  user,
  '@$user',
  user.toUpperCase(),
  ' $user ',
  'https://www.tiktok.com/@$user',
  'https://www.tiktok.com/@$user/live',
  'https://m.tiktok.com/@${user.toUpperCase()}/live/',
  'http://tiktok.com/@$user',
  'https://www.tiktok.com/@$user/video/7300000000000000000',
  'https://www.tiktok.com/@$user/live#chat',
  'https://user:pass@www.tiktok.com/@$user',
  'https://www.tiktok.com/@$user/../live',
  'https://vm.tiktok.com/ZMabcdef/',
  'https://www.tiktok.com/t/ZTabcdef/',
  'https://www.tiktok.com/share/live/$_shareRoomId',
  'https://www.tiktok.com/share/live/123',
  'https://www.tiktok.evil.com/@$user',
  'not a user!',
  'a..b',
  '_',
  '',
];

/// `api-live/user/room`: room entry, refresh, recording, the live status,
/// search, the link rules, qualities and URLs.
Future<void> _user(String sample, String user) async {
  _replay([sample]);
  final value = await _userCalls(user);
  value['links'] = {
    for (final input in _inputs(user))
      input: {
        'TikTokLink.parse': _link(TikTokLink.parse(input)),
        'TikTokLink.parseOrUsername': _link(TikTokLink.parseOrUsername(input)),
        'TikTokLink.parseDurableUsername': TikTokLink.parseDurableUsername(input),
        'TikTokLink.normalizeUsername': TikTokLink.normalizeUsername(input),
        'WebSearchRoomParser.parse': _webSearchTarget(input),
      },
  };
  value['TikTokLink.url'] = await _outcome(() => TikTokLink.url(user), (url) => url);
  final site = _site();
  value['getDirectoryPage'] = await _traced(() => site.getDirectoryPage(), _page);
  value['getDirectoryPage(page: 2)'] = await _traced(() => site.getDirectoryPage(page: 2), _page);
  value['getRecommendRooms'] = await _traced(() => site.getRecommendRooms(), _rooms);
  if (sample != 'S01-user-missing') {
    _replay([sample], rewrite: _trustedHosts);
    value['trustedHosts'] = await _userCalls(user, search: false);
  }
  _write(
    sample,
    'TikTokSite.getRoomDetailForRefresh + getRoomDetail + getRoomDetailForRecording + getLiveStatus + searchRooms + '
    'getPlayQualites + getPlayUrls + resolvePlayUrlsRaw + resolvePlayUrlsForRecoveryRaw + getDirectoryPage + '
    'getRecommendRooms; TikTokLink.parse + parseOrUsername + parseDurableUsername + normalizeUsername + url; '
    'WebSearchRoomParser.parse (TikTok step)'
    '${sample == 'S01-user-missing' ? '' : '; trustedHosts: the same calls over this answer with tiktokcdn-us.com '
              'spelled tiktokcdn.com (3.x trusted only the latter)'}',
    value,
  );
}

Future<Map<String, Object?>> _userCalls(String user, {bool search = true}) async {
  final site = _site();
  final value = <String, Object?>{
    for (final roomId in [user, user.toUpperCase(), '@$user'])
      'getRoomDetailForRefresh($roomId)': await _traced(
        () => site.getRoomDetailForRefresh(roomId: roomId, platform: 'tiktok'),
        _roomProjection,
      ),
    'getRoomDetail': await _traced(() => site.getRoomDetail(roomId: user, platform: 'tiktok'), _roomProjection),
    'getRoomDetailForRecording': await _traced(
      () => site.getRoomDetailForRecording(roomId: user, platform: 'tiktok'),
      _roomProjection,
    ),
    'getLiveStatus': await _traced(() => site.getLiveStatus(roomId: user, platform: 'tiktok'), (live) => live),
    if (search) ...{
      for (final keyword in [
        user,
        '@$user',
        user.toUpperCase(),
        'https://www.tiktok.com/@$user/live',
        'https://vm.tiktok.com/ZMabcdef/',
        'not a user!',
        '',
      ])
        'searchRooms($keyword)': await _traced(() => site.searchRooms(keyword, pageSize: 20), _rooms),
      'searchRooms($user, page: 2)': await _traced(() => site.searchRooms(user, page: 2), _rooms),
    },
  };
  LiveRoom? detail;
  try {
    detail = await site.getRoomDetail(roomId: user, platform: 'tiktok');
  } on Object catch (error) {
    value['getPlayQualites'] = {'getRoomDetail': _errorProjection(error)};
  }
  if (detail != null) {
    final entered = detail;
    value['getPlayQualites'] = await _traced(() => site.getPlayQualites(detail: entered), _qualities);
    final qualities = await site.getPlayQualites(detail: entered).catchError((_) => <LivePlayQuality>[]);
    final probe = qualities.isEmpty ? [LivePlayQuality(quality: 'probe', id: 'h264:hd:flv')] : qualities;
    value['getPlayUrls'] = {
      for (final quality in probe)
        '${quality.id}': await _traced(() => site.getPlayUrls(detail: entered, quality: quality), (urls) => urls),
    };
    value['resolvePlayUrlsRaw'] = {
      for (final quality in probe)
        '${quality.id}': await _traced(() => site.resolvePlayUrlsRaw(detail: entered, quality: quality), _resolution),
    };
    value['resolvePlayUrlsForRecoveryRaw'] = await _traced(
      () => site.resolvePlayUrlsForRecoveryRaw(detail: entered, quality: probe.first),
      _resolution,
    );
    // A room without 3.x's snapshot (a follow card) cannot list or play.
    final card = await site.getRoomDetailForRefresh(roomId: user, platform: 'tiktok');
    value['getPlayQualites(refresh card)'] = await _outcome(() => site.getPlayQualites(detail: card), _qualities);
  }
  return value;
}

/// `webcast/room/info`: a share link's broadcast to its user, then the user
/// (S01-user-live answers it).
Future<void> _share() async {
  _replay(['S02-room-live', 'S01-user-live']);
  final link = 'https://www.tiktok.com/share/live/$_shareRoomId';
  final site = _site();
  final value = <String, Object?>{
    'TikTokApi.resolveReference': await _traced(
      () => _api().resolveReference(const TikTokLink(kind: TikTokLinkKind.roomId, id: _shareRoomId)),
      (username) => username,
    ),
    'searchRooms(share link)': await _traced(() => site.searchRooms(link, pageSize: 20), _rooms),
    'LiveUrlTool.parseLiveUrl (TikTok step)': await _traced(() => _importTikTok('分享直播 $link 快来'), (id) => id),
    'LiveUrlTool.parseLiveUrl (TikTok step, user link)': await _traced(
      () => _importTikTok('https://www.tiktok.com/@QVC/live'),
      (id) => id,
    ),
  };
  _write(
    'S02-room-live',
    'TikTokApi.resolveReference + TikTokSite.searchRooms (with S01-user-live) + the TikTok step of '
        'LiveUrlTool._parseLiveUrl',
    value,
  );
}

Object? _link(TikTokLink? link) => link == null ? null : {'kind': link.kind.name, 'id': link.id};

/// 3.x's WebSearchRoomParser, TikTok step (web_search_room_parser.dart:98-99).
Object? _webSearchTarget(String input) {
  final tiktok = TikTokLink.parseDurableUsername(input);
  return tiktok == null ? null : ['tiktok', tiktok];
}

/// The TikTok step of 3.x's `LiveUrlTool._parseLiveUrl` (live_url_tool.dart:
/// 229-234) over the http links of [text] (`sharedHttpUrls`, reduced to a
/// space split: the inputs have no Chinese punctuation glued to the link).
Future<List<String>> _importTikTok(String text) async {
  for (final raw in text.split(RegExp(r'\s+')).where((part) => part.startsWith('http'))) {
    final tiktok = TikTokLink.parse(raw);
    if (tiktok != null) {
      final username = await _api().resolveReference(tiktok);
      return [username, 'tiktok'];
    }
  }
  return [];
}

// Stubs -----------------------------------------------------------------------

/// 3.x's zh.json text of the keys the TikTok classes use.
String i18n(String key) => switch (key) {
  'tiktok_chat_notice' => 'TikTok LIVE 远端聊天尚待接入；当前观看与累计进房分别展示。',
  'tiktok_quality_origin' => '原始画质',
  'tiktok_quality_uhd60' => '超清 60 帧',
  'tiktok_quality_hd60' => '高清 60 帧',
  'tiktok_quality_uhd' => '超清',
  'tiktok_quality_hd' => '高清',
  'tiktok_quality_sd' => '标清',
  'tiktok_quality_ld' => '流畅',
  'tiktok_quality_auto' => '自动',
  _ => throw StateError('no text for $key'),
};

class CancelToken {
  bool isCancelled = false;

  static bool isCancel(Object error) => false;
}

class DioException implements Exception {}

// 3.x's http_header_policy.dart (normalize) -----------------------------------

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

// 3.x models (the parts the TikTok classes use) ---------------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

class LiveArea {}

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

// 3.x's tiktok_api.dart ---------------------------------------------------------

enum TikTokFailure {
  transport,
  access,
  rateLimited,
  service,
  missing,
  schema,
  cancelled,
  identity,
  unknownState,
  mediaUnavailable,
}

class TikTokException implements Exception {
  const TikTokException(this.kind);

  final TikTokFailure kind;

  @override
  String toString() => 'TikTok ${kind.name}';
}

enum TikTokState { live, offline, restricted, unknown }

class TikTokStream {
  TikTokStream({
    required this.id,
    required this.qualityId,
    required this.protocol,
    required this.codec,
    required this.resolution,
    required this.bitrate,
    required Iterable<Uri> urls,
  }) : urls = List.unmodifiable(urls);

  final String id;
  final String qualityId;
  final String protocol;
  final String codec;
  final String resolution;
  final int? bitrate;
  final List<Uri> urls;
}

class TikTokRoom {
  TikTokRoom({
    required this.username,
    required this.userId,
    required this.secUid,
    required this.roomId,
    required this.streamId,
    required this.nickname,
    required this.title,
    required this.avatar,
    required this.cover,
    required this.bio,
    required this.followers,
    required this.currentViewers,
    required this.totalViewers,
    required this.verified,
    required this.state,
    required Iterable<TikTokStream> streams,
  }) : streams = List.unmodifiable(streams);

  final String username;
  final String userId;
  final String secUid;
  final String roomId;
  final String streamId;
  final String nickname;
  final String title;
  final String avatar;
  final String cover;
  final String bio;
  final int? followers;
  final int? currentViewers;
  final int? totalViewers;
  final bool verified;
  final TikTokState state;
  final List<TikTokStream> streams;
}

typedef TikTokRequest = Future<({int status, String body})> Function({
  required Uri uri,
  required Map<String, String> headers,
  CancelToken? cancel,
});

class TikTokApi {
  TikTokApi({required TikTokRequest request}) : _request = request;

  static const origin = 'https://www.tiktok.com';
  static const webcastOrigin = 'https://webcast.tiktok.com';
  static const responseLimit = 12 * 1024 * 1024;
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  final TikTokRequest _request;

  static Map<String, String> requestHeaders({String? username}) => {
    'User-Agent': userAgent,
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Origin': origin,
    'Referer': username == null ? '$origin/live' : TikTokLink.url(username),
  };

  static Map<String, String> mediaHeaders(String username) => {
    'User-Agent': userAgent,
    'Origin': origin,
    'Referer': TikTokLink.url(username),
  };

  Future<Map<String, dynamic>> _json(Uri uri, {String? username, CancelToken? cancel}) async {
    if (cancel?.isCancelled == true) throw const TikTokException(TikTokFailure.cancelled);
    late final ({int status, String body}) response;
    try {
      response = await _request(
        uri: uri,
        headers: requestHeaders(username: username),
        cancel: cancel,
      );
    } catch (error) {
      if (cancel?.isCancelled == true || (error is DioException && CancelToken.isCancel(error))) {
        throw const TikTokException(TikTokFailure.cancelled);
      }
      if (error is TikTokException) rethrow;
      // The harness has no network: a request without a sample is a harness
      // error, not 3.x's transport failure.
      if (error is StateError) rethrow;
      throw const TikTokException(TikTokFailure.transport);
    }
    if (cancel?.isCancelled == true) throw const TikTokException(TikTokFailure.cancelled);
    final failure = switch (response.status) {
      200 => null,
      400 => TikTokFailure.schema,
      401 || 403 => TikTokFailure.access,
      404 => TikTokFailure.missing,
      420 || 429 => TikTokFailure.rateLimited,
      >= 500 => TikTokFailure.service,
      _ => TikTokFailure.transport,
    };
    if (failure != null) throw TikTokException(failure);
    if (response.body.isEmpty) throw const TikTokException(TikTokFailure.access);
    if (response.body.length > responseLimit) throw const TikTokException(TikTokFailure.schema);
    try {
      return _object(jsonDecode(response.body));
    } on FormatException {
      throw const TikTokException(TikTokFailure.schema);
    }
  }

  Future<String> resolveReference(TikTokLink reference, {CancelToken? cancel}) async {
    switch (reference.kind) {
      case TikTokLinkKind.username:
        return _username(reference.id);
      case TikTokLinkKind.roomId:
        return _usernameFromRoomId(reference.id, cancel: cancel);
    }
  }

  Future<TikTokRoom> room(String rawUsername, {required bool includeMedia, CancelToken? cancel}) async {
    final username = TikTokLink.normalizeUsername(rawUsername);
    if (username == null) throw const TikTokException(TikTokFailure.identity);
    final root = await _json(
      Uri.parse('$origin/api-live/user/room/')
          .replace(queryParameters: {'aid': '1988', 'sourceType': '54', 'staleTime': '600000', 'uniqueId': username}),
      username: username,
      cancel: cancel,
    );
    final statusCode = _integer(root['statusCode']);
    if (statusCode != 0) {
      final message = _optionalText(root['message']).toLowerCase();
      throw TikTokException(
        statusCode == 19881007 || message.contains('not exist') || message.contains('not_found')
            ? TikTokFailure.missing
            : TikTokFailure.service,
      );
    }
    final data = _object(root['data']);
    final user = _object(data['user']);
    final stats = _optionalObject(data['stats']);
    final live = _object(data['liveRoom']);
    final actualUsername = _username(user['uniqueId']);
    if (actualUsername != username) throw const TikTokException(TikTokFailure.identity);

    final liveStatus = _integer(live['status'] ?? user['status']);
    final paidValue = live['paidEvent'];
    final paid = paidValue == null || (paidValue is List && paidValue.isEmpty)
        ? <String, dynamic>{}
        : _object(paidValue);
    final restricted =
        _optionalBool(user['secret']) == true ||
        _integer(live['liveSubOnly']) == 1 ||
        (_integer(paid['paid_type']) ?? 0) > 0;
    final state = restricted
        ? TikTokState.restricted
        : liveStatus == 2
        ? TikTokState.live
        : liveStatus == 4
        ? TikTokState.offline
        : TikTokState.unknown;
    final roomStats = _optionalObject(live['liveRoomStats']);
    final nickname = _text(user['nickname']);
    final title = _optionalText(live['title']);
    return TikTokRoom(
      username: username,
      userId: _longId(user['id']),
      secUid: _optionalText(user['secUid']),
      roomId: _optionalLongId(user['roomId']),
      streamId: _optionalLongId(live['streamId']),
      nickname: nickname,
      title: title.isEmpty ? nickname : title,
      avatar: _image(user['avatarLarger'] ?? user['avatarMedium'] ?? user['avatarThumb']),
      cover: _image(live['coverUrl'] ?? live['squareCoverImg']),
      bio: _optionalText(user['signature']),
      followers: _optionalNonNegativeInt(stats['followerCount']),
      currentViewers: state == TikTokState.live ? _optionalNonNegativeInt(roomStats['userCount']) : null,
      totalViewers: state == TikTokState.live ? _optionalNonNegativeInt(roomStats['enterCount']) : null,
      verified: _optionalBool(user['verified']) ?? false,
      state: state,
      streams: state == TikTokState.live && includeMedia ? _streams(live) : const [],
    );
  }

  Future<String> _usernameFromRoomId(String rawRoomId, {CancelToken? cancel}) async {
    final roomId = TikTokLink.normalizeRoomId(rawRoomId);
    if (roomId == null) throw const TikTokException(TikTokFailure.identity);
    final root = await _json(
      Uri.parse('$webcastOrigin/webcast/room/info/').replace(queryParameters: {'aid': '1988', 'room_id': roomId}),
      cancel: cancel,
    );
    if (_integer(root['status_code']) != 0) throw const TikTokException(TikTokFailure.missing);
    final data = _object(root['data']);
    if (_longId(data['id']) != roomId) throw const TikTokException(TikTokFailure.identity);
    return _username(_object(data['owner'])['display_id']);
  }

  static List<TikTokStream> _streams(Map<String, dynamic> room) {
    final builders = <String, _TikTokStreamBuilder>{};
    void readContainer(Object? value, String fallbackCodec) {
      if (value == null) return;
      final container = _object(value);
      final pull = _object(container['pull_data']);
      final raw = _optionalText(pull['stream_data']);
      if (raw.isEmpty || raw.length > 4 * 1024 * 1024) return;
      final decoded = _object(_decode(raw));
      final qualities = _object(decoded['data']);
      if (qualities.length > 32) throw const TikTokException(TikTokFailure.schema);
      for (final entry in qualities.entries) {
        final qualityId = _qualityId(entry.key);
        if (qualityId == 'ao') continue;
        final main = _object(_object(entry.value)['main']);
        final sdkRaw = _optionalText(main['sdk_params']);
        final sdk = sdkRaw.isEmpty ? <String, dynamic>{} : _object(_decode(sdkRaw));
        final codec = _codec(sdk['VCodec'] ?? sdk['v_codec'], fallbackCodec);
        final resolution = _resolution(sdk['resolution']);
        final bitrate = _optionalNonNegativeInt(sdk['vbitrate']);
        for (final protocol in const ['flv', 'hls']) {
          final rawUrl = _optionalText(main[protocol]);
          if (rawUrl.isEmpty) continue;
          final uri = _mediaUri(rawUrl);
          final id = '$codec:$qualityId:$protocol';
          final builder = builders.putIfAbsent(
            id,
            () => _TikTokStreamBuilder(
              id: id,
              qualityId: qualityId,
              protocol: protocol,
              codec: codec,
              resolution: resolution,
              bitrate: bitrate,
            ),
          );
          if (builder.resolution.isEmpty && resolution.isNotEmpty) builder.resolution = resolution;
          builder.bitrate ??= bitrate;
          if (!builder.urls.contains(uri)) builder.urls.add(uri);
        }
      }
    }

    readContainer(room['streamData'], 'h264');
    readContainer(room['hevcStreamData'], 'h265');
    final streams = builders.values
        .where((value) => value.urls.isNotEmpty)
        .map(
          (value) => TikTokStream(
            id: value.id,
            qualityId: value.qualityId,
            protocol: value.protocol,
            codec: value.codec,
            resolution: value.resolution,
            bitrate: value.bitrate,
            urls: value.urls,
          ),
        )
        .toList(growable: false);
    streams.sort((left, right) {
      final rank = qualitySort(right).compareTo(qualitySort(left));
      return rank != 0 ? rank : left.id.compareTo(right.id);
    });
    return List.unmodifiable(streams);
  }

  static int qualitySort(TikTokStream stream) {
    final quality = switch (stream.qualityId) {
      'origin' => 10000,
      'uhd_60' => 9000,
      'hd_60' => 8000,
      'uhd' => 7000,
      'hd' => 6000,
      'sd' => 5000,
      'ld' => 4000,
      'auto' => 3000,
      _ => 1000,
    };
    final codec = stream.codec == 'h264' ? 100 : 0;
    final protocol = stream.protocol == 'flv' ? 20 : 10;
    return quality + codec + protocol;
  }

  static Object? _decode(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      throw const TikTokException(TikTokFailure.schema);
    }
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map) throw const TikTokException(TikTokFailure.schema);
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static Map<String, dynamic> _optionalObject(Object? value) {
    if (value == null) return <String, dynamic>{};
    return _object(value);
  }

  static int? _integer(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static int? _optionalNonNegativeInt(Object? value) {
    if (value == null || value == '') return null;
    final result = _integer(value);
    if (result == null || result < 0) throw const TikTokException(TikTokFailure.schema);
    return result;
  }

  static bool? _optionalBool(Object? value) {
    if (value == null) return null;
    if (value is! bool) throw const TikTokException(TikTokFailure.schema);
    return value;
  }

  static String _username(Object? value) {
    if (value is! String) throw const TikTokException(TikTokFailure.identity);
    final username = TikTokLink.normalizeUsername(value);
    if (username == null) throw const TikTokException(TikTokFailure.identity);
    return username;
  }

  static String _longId(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (!RegExp(r'^[1-9][0-9]{14,24}$').hasMatch(raw)) throw const TikTokException(TikTokFailure.schema);
    return raw;
  }

  static String _optionalLongId(Object? value) {
    if (value == null || value == '') return '';
    return _longId(value);
  }

  static String _text(Object? value) {
    if (value is! String || value.trim().isEmpty || value.length > 8192) {
      throw const TikTokException(TikTokFailure.schema);
    }
    return value.trim();
  }

  static String _optionalText(Object? value) {
    if (value == null || value == '') return '';
    if (value is! String || value.length > 4 * 1024 * 1024) {
      throw const TikTokException(TikTokFailure.schema);
    }
    return value.trim();
  }

  static String _qualityId(String raw) {
    final value = raw.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{1,24}$').hasMatch(value)) throw const TikTokException(TikTokFailure.schema);
    return value;
  }

  static String _codec(Object? value, String fallback) {
    final raw = _optionalText(value).toLowerCase();
    final codec = switch (raw) {
      '' => fallback,
      'avc' => 'h264',
      'hevc' => 'h265',
      'h264' || 'h265' => raw,
      _ => throw const TikTokException(TikTokFailure.schema),
    };
    return codec;
  }

  static String _resolution(Object? value) {
    final raw = _optionalText(value).toLowerCase();
    if (raw.isEmpty) return '';
    return RegExp(r'^(?:[1-9][0-9]{1,4}x[1-9][0-9]{1,4}|[1-9][0-9]{2,4}p)$').hasMatch(raw) ? raw : '';
  }

  static String _image(Object? value) {
    if (value is! String || value.length > 16384) return '';
    final uri = Uri.tryParse(value);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment || !_trustedHost(host)) {
      return '';
    }
    return value;
  }

  static Uri _mediaUri(String raw) {
    if (raw.length > 65536 || raw.contains(RegExp(r'[\s\x00-\x1f]'))) {
      throw const TikTokException(TikTokFailure.schema);
    }
    final uri = Uri.tryParse(raw);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment || !_trustedHost(host)) {
      throw const TikTokException(TikTokFailure.schema);
    }
    return uri;
  }

  static bool _trustedHost(String host) =>
      host == 'tiktokcdn.com' ||
      host.endsWith('.tiktokcdn.com') ||
      host == 'tiktokv.com' ||
      host.endsWith('.tiktokv.com') ||
      host == 'byteoversea.com' ||
      host.endsWith('.byteoversea.com');
}

class _TikTokStreamBuilder {
  _TikTokStreamBuilder({
    required this.id,
    required this.qualityId,
    required this.protocol,
    required this.codec,
    required this.resolution,
    required this.bitrate,
  });

  final String id;
  final String qualityId;
  final String protocol;
  final String codec;
  String resolution;
  int? bitrate;
  final List<Uri> urls = [];
}

// 3.x's tiktok_link.dart --------------------------------------------------------

enum TikTokLinkKind { username, roomId }

class TikTokLink {
  const TikTokLink({required this.kind, required this.id});

  final TikTokLinkKind kind;
  final String id;

  static TikTokLink? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !_officialHost(uri.host.toLowerCase())) {
      return null;
    }
    final segments = uri.pathSegments.where((value) => value.isNotEmpty).toList(growable: false);
    if (segments.any((value) => value == '.' || value == '..')) return null;
    if (segments.length == 1 && segments.first.startsWith('@')) {
      final username = normalizeUsername(segments.first.substring(1));
      return username == null ? null : TikTokLink(kind: TikTokLinkKind.username, id: username);
    }
    if (segments.length == 2 && segments.first.startsWith('@') && segments[1].toLowerCase() == 'live') {
      final username = normalizeUsername(segments.first.substring(1));
      return username == null ? null : TikTokLink(kind: TikTokLinkKind.username, id: username);
    }
    if (segments.length == 3 && segments[0].toLowerCase() == 'share' && segments[1].toLowerCase() == 'live') {
      final roomId = normalizeRoomId(segments[2]);
      return roomId == null ? null : TikTokLink(kind: TikTokLinkKind.roomId, id: roomId);
    }
    return null;
  }

  static TikTokLink? parseOrUsername(String raw) {
    final parsed = parse(raw);
    if (parsed != null) return parsed;
    final value = raw.trim().startsWith('@') ? raw.trim().substring(1) : raw.trim();
    final username = normalizeUsername(value);
    return username == null ? null : TikTokLink(kind: TikTokLinkKind.username, id: username);
  }

  static String? parseDurableUsername(String raw) {
    final parsed = parse(raw);
    if (parsed?.kind == TikTokLinkKind.username) return parsed!.id;
    return null;
  }

  static String? normalizeUsername(String raw) {
    final value = raw.trim().toLowerCase();
    return RegExp(r'^[a-z0-9_](?:[a-z0-9._]{0,22}[a-z0-9_])?$').hasMatch(value) ? value : null;
  }

  static String? normalizeRoomId(String raw) {
    final value = raw.trim();
    return RegExp(r'^[1-9][0-9]{14,24}$').hasMatch(value) ? value : null;
  }

  static String url(String rawUsername) {
    final username = normalizeUsername(rawUsername);
    if (username == null) throw const FormatException('Invalid TikTok username');
    return 'https://www.tiktok.com/@$username/live';
  }

  static bool isShortHost(String host) {
    final value = host.trim().toLowerCase();
    return value == 'vm.tiktok.com' || value == 'vt.tiktok.com';
  }

  static bool _officialHost(String host) => host == 'tiktok.com' || host == 'www.tiktok.com' || host == 'm.tiktok.com';
}

// 3.x's tiktok_site.dart --------------------------------------------------------

class TikTokSite {
  TikTokSite({TikTokApi? api}) : _api = api!;

  final TikTokApi _api;

  String get id => 'tiktok';

  String get name => 'TikTok LIVE';

  String get directoryNoticeKey => 'tiktok_directory_scope';

  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1 || category != null) throw const TikTokException(TikTokFailure.schema);
    return LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
  }

  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (page < 1 || pageSize < 1) return [];
    return const [];
  }

  LiveRoom _card(TikTokRoom room, {required bool includeMedia}) {
    final current = room.currentViewers?.toString();
    return LiveRoom(
      platform: id,
      roomId: room.username,
      userId: room.userId,
      nick: room.nickname,
      title: room.title,
      avatar: room.avatar,
      cover: room.cover,
      area: 'TikTok LIVE',
      followers: room.followers?.toString(),
      introduction: room.bio,
      link: TikTokLink.url(room.username),
      liveStatus: switch (room.state) {
        TikTokState.live => LiveStatus.live,
        TikTokState.offline => LiveStatus.offline,
        TikTokState.restricted => LiveStatus.banned,
        TikTokState.unknown => LiveStatus.unknown,
      },
      watching: current ?? '',
      onlineViewers: current,
      totalViewers: room.totalViewers?.toString(),
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: i18n('tiktok_chat_notice'),
      httpHeaders: TikTokApi.mediaHeaders(room.username),
      data: includeMedia ? room : null,
    );
  }

  String _roomId(String roomId, String platform) {
    if (platform.trim().toLowerCase() != id) throw const TikTokException(TikTokFailure.identity);
    final normalized = TikTokLink.normalizeUsername(roomId);
    if (normalized == null) throw const TikTokException(TikTokFailure.identity);
    return normalized;
  }

  Future<LiveRoom> _detail(String roomId, String platform, {required bool includeMedia}) async {
    final data = await _api.room(_roomId(roomId, platform), includeMedia: includeMedia);
    if (includeMedia && data.state == TikTokState.live && data.streams.isEmpty) {
      throw const TikTokException(TikTokFailure.mediaUnavailable);
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
      throw const TikTokException(TikTokFailure.unknownState);
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
    final reference = TikTokLink.parseOrUsername(keyword);
    if (reference == null) return [];
    try {
      final username = await _api.resolveReference(reference, cancel: cancel);
      return [_card(await _api.room(username, includeMedia: false, cancel: cancel), includeMedia: false)];
    } on TikTokException catch (error) {
      if (error.kind == TikTokFailure.missing) return [];
      rethrow;
    }
  }

  TikTokRoom _snapshot(LiveRoom detail) {
    final roomId = _roomId(detail.roomId ?? '', detail.platform ?? '');
    final data = detail.data;
    if (data is! TikTokRoom || data.username != roomId || data.userId != detail.userId) {
      throw const TikTokException(TikTokFailure.identity);
    }
    if (data.state == TikTokState.unknown) throw const TikTokException(TikTokFailure.unknownState);
    if (data.state != TikTokState.live || detail.isExplicitlyOfflineNow || data.streams.isEmpty) {
      throw const TikTokException(TikTokFailure.mediaUnavailable);
    }
    return data;
  }

  static String _qualityName(TikTokStream stream) => switch (stream.qualityId) {
    'origin' => i18n('tiktok_quality_origin'),
    'uhd_60' => i18n('tiktok_quality_uhd60'),
    'hd_60' => i18n('tiktok_quality_hd60'),
    'uhd' => i18n('tiktok_quality_uhd'),
    'hd' => i18n('tiktok_quality_hd'),
    'sd' => i18n('tiktok_quality_sd'),
    'ld' => i18n('tiktok_quality_ld'),
    'auto' => i18n('tiktok_quality_auto'),
    _ => stream.qualityId.toUpperCase(),
  };

  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    if (detail.isExplicitlyOfflineNow) return [];
    final room = _snapshot(detail);
    return List.unmodifiable(
      room.streams.map((stream) {
        final resolution = stream.resolution.isEmpty ? '' : ' · ${stream.resolution}';
        return LivePlayQuality(
          id: stream.id,
          quality:
              '${_qualityName(stream)}$resolution · ${stream.codec.toUpperCase()} · ${stream.protocol.toUpperCase()}',
          sort: TikTokApi.qualitySort(stream),
        );
      }),
    );
  }

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality, {required bool refresh}) async {
    var room = _snapshot(detail);
    if (refresh) room = _snapshot(await getRoomDetail(roomId: room.username, platform: id));
    final qualityId = quality.selectionId.toString();
    for (final stream in room.streams) {
      if (stream.id == qualityId) {
        return LivePlayUrlResolution(
          urls: List.unmodifiable(stream.urls.map((uri) => uri.toString())),
          appliedQualityData: qualityId,
        );
      }
    }
    throw const TikTokException(TikTokFailure.mediaUnavailable);
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
