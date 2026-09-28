// Writes expected.json for the Xiaohongshu samples: 3.x's parsers run over
// the recorded responses (docs/modules/M4.16-xiaohongshu.md, "样本与 v3 的冻结
// 输出").
//
// The archive has no Xiaohongshu expected.json (its legacy harness only
// covered five platforms, and 3.x no longer builds). The code below is 3.x's
// XiaohongshuShare, XiaohongshuLink, XiaohongshuApi and XiaohongshuSite,
// copied from legacy/lib/core/site/xiaohongshu/ (archive/v4). 3.x already
// injected its transport (`XiaohongshuRequest`), so only that function is
// replaced: it answers from the samples by host and path, with the empty
// body 3.x read for any status other than 200, and throws a StateError for a
// request without a sample. The short-link session is reduced to what
// `XiaohongshuLink.resolve` uses (the visited-URL budget, no redirect
// following, the recorded status and `Location`). Dio's CancelToken, the
// request scope and the deadline race are left out (no request here can
// hang); `readBody` only ran on the network path. `i18n` returns 3.x's
// zh.json text. 3.x's LiveRoom and LivePlayQuality are reduced to the parts
// these classes use. The output format is the legacy harness's
// (`roomProjection`, `errorProjection`, `{generator, value}`).
//
// 3.x found the hydration script with package:html, which the workspace does
// not depend on, so this runs with a throwaway package configuration. From
// the repository root:
//
//   d=$(mktemp -d)
//   printf 'name: g\nenvironment:\n  sdk: ^3.9.0\ndependencies:\n  html: 0.15.6\n' > "$d/pubspec.yaml"
//   (cd "$d" && dart pub get)
//   dart --packages="$d/.dart_tool/package_config.json" fixtures/xiaohongshu/legacy_expected.dart
//
// Review the diff of every expected.json before committing it.
// ignore_for_file: type=lint
import 'dart:convert';
import 'dart:io';

import 'package:html/parser.dart' as html;

const _root = 'fixtures/xiaohongshu';

const _live = '570459564696889177';
const _ended = '570305058583373361';
const _missing = '569865232324657152';

void main() async {
  await _room('S01-room-live', _live);
  await _room('S01-room-ended', _ended);
  await _room('S01-room-notfound', _missing);
  await _shortLink();
}

// Harness ---------------------------------------------------------------------

List<Map<String, dynamic>> _samples = [];
final List<Uri> _requests = [];

Map<String, dynamic> _meta(String sample) =>
    jsonDecode(File('$_root/$sample/meta.json').readAsStringSync()) as Map<String, dynamic>;

void _load(List<String> samples) {
  _samples = [for (final sample in samples) _meta(sample)];
  _requests.clear();
}

Map<String, dynamic> _sampleFor(Uri uri) => _samples.firstWhere((meta) {
  final recorded = Uri.parse((meta['request'] as Map)['url'] as String);
  return recorded.host == uri.host && recorded.path == uri.path;
}, orElse: () => throw StateError('No recorded sample for GET $uri'));

/// 3.x's `_defaultRequest` over the samples: no redirect following, and the
/// body is read only for a 200.
Future<({int status, String body})> _replay(Uri uri, Object? cancel) async {
  _requests.add(uri);
  final meta = _sampleFor(uri);
  final status = (meta['response'] as Map<String, dynamic>)['status'] as int;
  if (status != 200) return (status: status, body: '');
  return (status: 200, body: File('$_root/${meta['sample']}/${meta['body']}').readAsStringSync());
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
Future<Object?> _outcome<T>(Future<T> Function() body, Object? Function(T value) project) async {
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
    (key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty),
  );
  return json;
}

List<Map<String, dynamic>> _rooms(List<LiveRoom> rooms) => [for (final room in rooms) _roomProjection(room)];

// Samples ---------------------------------------------------------------------

/// Every entry 3.x had for one room page: room entry, follow refresh,
/// recording detail, state, exact search by id and by share link (and its
/// page 2), qualities with their URLs, recovery.
Future<void> _room(String sample, String roomId) async {
  _load([sample]);
  final site = XiaohongshuSite(api: XiaohongshuApi(request: _replay));
  final link = 'https://www.xiaohongshu.com/livestream/$roomId?share_id=fixture';
  final value = <String, Object?>{
    'getRoomDetail': await _outcome(
      () => site.getRoomDetail(roomId: roomId, platform: 'xiaohongshu'),
      _roomProjection,
    ),
    'getRoomDetailForRefresh': await _outcome(
      () => site.getRoomDetailForRefresh(roomId: roomId, platform: 'xiaohongshu'),
      _roomProjection,
    ),
    'getRoomDetailForRecording': await _outcome(
      () => site.getRoomDetailForRecording(roomId: roomId, platform: 'xiaohongshu'),
      _roomProjection,
    ),
    'getLiveStatus': await _outcome(() => site.getLiveStatus(roomId: roomId, platform: 'xiaohongshu'), (live) => live),
    'searchRooms(roomId)': await _outcome(() => site.searchRooms(roomId), _rooms),
    'searchRooms(link)': await _outcome(() => site.searchRooms(link), _rooms),
    'searchRooms(link, page 2)': await _outcome(() => site.searchRooms(link, page: 2), _rooms),
  };
  try {
    final detail = await site.getRoomDetail(roomId: roomId, platform: 'xiaohongshu');
    final qualities = await site.getPlayQualites(detail: detail);
    value['getPlayQualites'] = [
      for (final quality in qualities)
        {
          'quality': quality.quality,
          'id': quality.id,
          'sort': quality.sort,
          'getPlayUrls': await site.getPlayUrls(detail: detail, quality: quality),
          'resolvePlayUrlsForRecovery': await _outcome(
            () => site.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: quality),
            (resolution) => {'urls': resolution.urls, 'appliedQualityData': resolution.appliedQualityData},
          ),
        },
    ];
    // What playback of a quality the room does not list gives (3.x's
    // getPlayUrls on an offline room, or a stale quality).
    value['getPlayUrls(h264:HD)'] = await _outcome(
      () => site.getPlayUrls(
        detail: detail,
        quality: _LegacyQuality(id: 'h264:HD', quality: '原画 · H264'),
      ),
      (urls) => urls,
    );
  } on StateError {
    rethrow;
  } on Object catch (error) {
    value['getPlayQualites'] = _errorProjection(error);
  }
  _write(
    sample,
    'XiaohongshuSite.getRoomDetail + getRoomDetailForRefresh + getRoomDetailForRecording + getLiveStatus + '
    'searchRooms(id, link) + getPlayQualites + getPlayUrls + resolvePlayUrlsForRecoveryRaw',
    value,
  );
}

/// An expired short link: search resolves it one hop at a time without
/// following redirects; the hop lands on the home page, which is no room.
Future<void> _shortLink() async {
  _load(['S02-shortlink-expired']);
  final site = XiaohongshuSite(api: XiaohongshuApi(request: _replay));
  const link = 'https://xhslink.com/m/18ox3lAz';
  final session = LiveShortLinkSession();
  final value = <String, Object?>{
    'XiaohongshuLink.resolve': await _outcome(() => XiaohongshuLink.resolve(link, session: session), (id) => id),
    'searchRooms(shortLink)': await _outcome(() => site.searchRooms('看直播 $link'), _rooms),
    'searchRooms(shortLink only)': await _outcome(() => site.searchRooms(link), _rooms),
  };
  _write('S02-shortlink-expired', 'XiaohongshuLink.resolve + XiaohongshuSite.searchRooms (short link)', value);
}

// 3.x's i18n (assets/translations/zh.json) ----------------------------------------

const Map<String, String> _zh = {
  'site_xiaohongshu': '小红书',
  'xiaohongshu_directory_scope':
      '暂无已接入的公开直播目录。请在搜索页输入直播房间号，或导入官网 /livestream/ 分享链接；收藏仅跟踪该直播房间，不代表跨场次跟随主播。',
  'xiaohongshu_display_viewers': '平台展示观看值：{value}（非已验证的实时在线人数）',
  'xiaohongshu_restricted': '该房间存在访问条件或访问状态待确认，当前没有可用的公开完整直播源。',
  'xiaohongshu_room_scope': '当前以直播房间号跟踪；主播重新开播使用新房间号时，请重新导入分享链接。',
};

String i18n(String key, {Map<String, String>? args}) {
  var text = _zh[key] ?? (throw StateError('No zh.json text for $key'));
  for (final MapEntry(:key, :value) in (args ?? const <String, String>{}).entries) {
    text = text.replaceAll('{$key}', value);
  }
  return text;
}

// 3.x's short-link session (legacy/lib/common/utils/live_short_link_session.dart),
// over the samples ------------------------------------------------------------

class _Response {
  _Response(this.statusCode, this.headers);

  final int statusCode;
  final Map<String, List<String>> headers;
}

class LiveShortLinkSession {
  final _visited = <String>{};
  bool _closed = false;
  bool get isClosed => _closed;
  static const maxRequests = 8;
  static const redirectStatuses = {301, 302, 303, 307, 308};

  static bool isHttpUri(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty && uri.userInfo.isEmpty;

  /// 3.x's `get`: no redirect following; 2xx and 3xx are answers, anything
  /// else is null.
  Future<_Response?> get(Uri uri, {bool json = false, Map<String, dynamic>? headers}) async {
    final requestUri = uri.removeFragment();
    if (_closed || !isHttpUri(uri) || _visited.length >= maxRequests || !_visited.add(requestUri.toString())) {
      return null;
    }
    _requests.add(requestUri);
    final response = _sampleFor(requestUri)['response'] as Map<String, dynamic>;
    final status = response['status'] as int;
    if (status < 200 || status >= 400) return null;
    final location = (response['headers'] as Map<String, dynamic>)['location'];
    return _closed
        ? null
        : _Response(status, {
            if (location is String) 'location': [location],
          });
  }

  void close() => _closed = true;
}

// 3.x models (the parts the Xiaohongshu adapter uses) ------------------------

enum LiveStatus { live, offline, replay, unknown, banned }

enum AudienceMetricType { popularity, onlineViewers, totalViewers, followers, unknown }

class _LegacyQuality {
  _LegacyQuality({required this.quality, this.data, this.id, this.sort = 0});

  final String quality;
  final dynamic data;
  final Object? id;
  final int sort;

  Object get selectionId => id ?? quality;
}

typedef LivePlayQuality = _LegacyQuality;

class LivePlayUrlResolution {
  const LivePlayUrlResolution({required this.urls, this.appliedQualityData});

  final List<String> urls;
  final Object? appliedQualityData;
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

  bool get isPlayableNow => isLiveNow || effectiveLiveStatus == LiveStatus.replay;

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

// 3.x's xiaohongshu_share.dart (unchanged) ------------------------------------

enum XiaohongshuFailure {
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
}

class XiaohongshuException implements Exception {
  const XiaohongshuException(this.kind);
  final XiaohongshuFailure kind;
  @override
  String toString() => 'Xiaohongshu ${kind.name}';
}

enum XiaohongshuAccess { public, restricted, unknown }

class XiaohongshuStream {
  const XiaohongshuStream({required this.uri, required this.codec, required this.quality, required this.label});
  final Uri uri;
  final String codec;
  final String quality;
  final String label;
  String get protocol => uri.path.endsWith('.m3u8') ? 'hls' : 'flv';
}

/// Public share-page snapshot, not a persistent broadcaster identity or a
/// directory. Ended pages can omit roomId and include an unrelated recommendation.
class XiaohongshuShare {
  const XiaohongshuShare({
    required this.requestedRoomId,
    required this.responseRoomId,
    required this.reportedStatus,
    required this.reportedLive,
    required this.access,
    required this.title,
    required this.nickname,
    required this.cover,
    required this.avatar,
    required this.displayViewers,
    required this.streams,
  });

  final String requestedRoomId;
  final String? responseRoomId;
  final int reportedStatus;
  final bool? reportedLive;
  final XiaohongshuAccess access;
  final String? title;
  final String? nickname;
  final String? cover;
  final String? avatar;
  // Platform display text, not measured concurrent viewers or an integer count.
  final String? displayViewers;
  final List<XiaohongshuStream> streams;

  static const responseLimit = 2 * 1024 * 1024;

  static String validateRoomId(String id) {
    if (!RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(id)) {
      throw const XiaohongshuException(XiaohongshuFailure.identity);
    }
    return id;
  }

  /// Accept a JSON-shaped hydration assignment with bare undefined placeholders.
  /// Never execute scripts, replace inside strings, or accept other JS syntax.
  /// The caller must bind this body to the requested URL without auto-redirects.
  static XiaohongshuShare parsePage(String page, {required String roomId}) {
    validateRoomId(roomId);
    if (page.length > responseLimit || utf8.encode(page).length > responseLimit) {
      throw const XiaohongshuException(XiaohongshuFailure.schema);
    }
    const marker = 'window.__INITIAL_STATE__=';
    final scripts = html
        .parse(page)
        .querySelectorAll('script')
        .where((s) => s.text.trimLeft().startsWith(marker))
        .toList();
    if (scripts.length != 1) throw const XiaohongshuException(XiaohongshuFailure.schema);
    var source = scripts.single.text.trim().substring(marker.length).trim();
    if (source.endsWith(';')) source = source.substring(0, source.length - 1).trimRight();
    try {
      final root = _object(jsonDecode(_hydrationJson(source)));
      return parseState(_object(root['liveStream']), roomId: roomId);
    } on FormatException {
      throw const XiaohongshuException(XiaohongshuFailure.schema);
    }
  }

  // The current server emits undefined for optional global configuration, even
  // when liveStream itself is JSON. A global String.replaceAll would corrupt
  // titles/URLs containing that word. This scanner only converts bare tokens;
  // jsonDecode still validates the complete result (no comments/functions/etc.).
  static String _hydrationJson(String source) {
    final result = StringBuffer();
    var quoted = false;
    var escaped = false;
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (quoted) {
        result.write(char);
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          quoted = false;
        }
      } else if (char == '"') {
        quoted = true;
        result.write(char);
      } else if (source.startsWith('undefined', i)) {
        result.write('null');
        i += 'undefined'.length - 1;
      } else {
        result.write(char);
      }
    }
    return result.toString();
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value is! Map<String, dynamic>) throw const XiaohongshuException(XiaohongshuFailure.schema);
    return value;
  }

  static String? _text(Object? value, {int limit = 4096}) {
    if (value == null) return null;
    if (value is! String || value.length > limit) throw const XiaohongshuException(XiaohongshuFailure.schema);
    return value;
  }

  static XiaohongshuShare parseState(Map<String, dynamic> state, {required String roomId}) {
    validateRoomId(roomId);
    // The frontend uses the same page error for network, missing-room and
    // restricted responses. Its generic message does not prove any one cause.
    if (state['pageStatus'] == 'error') throw const XiaohongshuException(XiaohongshuFailure.api);
    if (state['pageStatus'] != 'success') throw const XiaohongshuException(XiaohongshuFailure.schema);
    final data = _object(state['roomData']);
    final room = _object(data['roomInfo']);
    final host = _object(data['hostInfo']);
    final responseId = room['roomId'];
    if (responseId != null && (responseId is! String || responseId != roomId)) {
      throw const XiaohongshuException(XiaohongshuFailure.identity);
    }
    final status = room['status'];
    if (status is! int || status < 0) throw const XiaohongshuException(XiaohongshuFailure.schema);
    final liveStatus = state['liveStatus'];
    // Observed 2 = live and 3 = ended. Future states remain unknown; the
    // frontend's default "success" alone is not positive live evidence.
    final bool? live = switch (status) {
      2 => true,
      3 => false,
      _ => null,
    };
    if ((live == true && liveStatus != 'success') || (live == false && liveStatus != 'end')) {
      throw const XiaohongshuException(XiaohongshuFailure.schema);
    }
    if (live == true && responseId == null) throw const XiaohongshuException(XiaohongshuFailure.identity);

    final monetization = room['monetizeType'];
    final limits = room['joinLimitTypes'];
    if (monetization != null && (monetization is! int || monetization < 0)) {
      throw const XiaohongshuException(XiaohongshuFailure.schema);
    }
    if (limits != null && (limits is! List || limits.length > 16 || limits.any((v) => v is! int || v < 0))) {
      throw const XiaohongshuException(XiaohongshuFailure.schema);
    }
    final access = monetization == null || limits == null
        ? XiaohongshuAccess.unknown
        : monetization != 0 || (limits as List).any((v) => v != 0)
        ? XiaohongshuAccess.restricted
        : XiaohongshuAccess.public;
    // nextRoomInfo, deeplink preload URLs and replayInfo are deliberately not
    // media sources for this room, nor proof that this room is live.
    final streams = live == true && access == XiaohongshuAccess.public
        ? _streams(room['pullConfig'], roomId)
        : <XiaohongshuStream>[];
    return XiaohongshuShare(
      requestedRoomId: roomId,
      responseRoomId: responseId as String?,
      reportedStatus: status,
      reportedLive: live,
      access: access,
      title: _text(room['roomTitle']),
      nickname: _text(host['nickName']),
      cover: _text(room['roomCover']),
      avatar: _text(host['avatar']),
      displayViewers: _text(room['displayViewerCount']),
      streams: List.unmodifiable(streams),
    );
  }

  static List<XiaohongshuStream> _streams(Object? value, String roomId) {
    if (value == null || value == '') return [];
    if (value is! String || value.length > 65536) throw const XiaohongshuException(XiaohongshuFailure.schema);
    late Map<String, dynamic> config;
    try {
      config = _object(jsonDecode(value));
    } on FormatException {
      throw const XiaohongshuException(XiaohongshuFailure.schema);
    }
    final result = <XiaohongshuStream>[];
    final identities = <String>{};
    for (final codec in ['h264', 'h265']) {
      final rows = config[codec];
      if (rows == null) continue;
      if (rows is! List || rows.length > 32) throw const XiaohongshuException(XiaohongshuFailure.schema);
      for (final value in rows) {
        final row = _object(value);
        final url = _text(row['master_url']);
        final quality = _text(row['quality_type'], limit: 64);
        final label = _text(row['quality_type_name'], limit: 128);
        if (url == null || quality == null || quality.isEmpty || label == null || label.isEmpty) {
          throw const XiaohongshuException(XiaohongshuFailure.schema);
        }
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            !(uri.host.endsWith('.xhscdn.com') && uri.host != '.xhscdn.com') ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment ||
            uri.port != (uri.scheme == 'https' ? 443 : 80) ||
            !['/live/$roomId.m3u8', '/live/$roomId.flv'].contains(uri.path)) {
          throw const XiaohongshuException(XiaohongshuFailure.schema);
        }
        // Preserve full query, declared scheme, quality and codec. Duplicate
        // aliases of the same source do not create extra selectable streams.
        if (identities.add('$codec|$quality|$uri')) {
          result.add(XiaohongshuStream(uri: uri, codec: codec, quality: quality, label: label));
        }
      }
    }
    return result;
  }
}

// 3.x's xiaohongshu_link.dart (unchanged) -------------------------------------

/// Broadcast room identity only. Profile IDs, notes and recommended rooms are
/// not aliases. Resolve short links only within the observed share hosts/routes.
class XiaohongshuLink {
  /// The official app deep link names a room; flvUrl is only a preload hint.
  /// Import the identity and let the normal room API resolve current media.
  static String? deepLinkRoomId(String raw) {
    final value = raw.trim();
    if (value.length > 8192 || value.contains(RegExp(r'[\x00-\x20\x7f]'))) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme.toLowerCase() != 'xhsdiscover' ||
        uri.host.toLowerCase() != 'live_audience' ||
        uri.path.isNotEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.hasFragment) {
      return null;
    }
    try {
      final room = uri.queryParametersAll['room_id'];
      final source = uri.queryParametersAll['source'];
      if (room?.length != 1 || source?.length != 1 || source!.single.trim().isEmpty) return null;
      final id = room!.single;
      return RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(id) ? id : null;
    } on FormatException {
      return null;
    }
  }

  static bool _plainPath(String value) {
    if (value.length > 8192 || value.contains(RegExp(r'[\x00-\x20\x7f]'))) return false;
    final path = value.split(RegExp(r'[?#]')).first;
    return !path.contains('%') && !path.contains('\\') && !RegExp(r'(^|/)\.\.?(/|$)').hasMatch(path);
  }

  static Uri? _webUri(String raw) {
    final value = raw.trim();
    if (!_plainPath(value)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    return uri;
  }

  static String? parse(String raw) {
    final value = raw.trim();
    if (RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(value)) return value;
    final deepLink = deepLinkRoomId(value);
    if (deepLink != null) return deepLink;
    final uri = _webUri(value);
    if (uri == null || !{'www.xiaohongshu.com', 'xiaohongshu.com'}.contains(uri.host)) {
      return null;
    }
    final canonical = RegExp(r'^/livestream/([1-9][0-9]{0,19})/?$').firstMatch(uri.path);
    if (canonical != null) return canonical[1];
    // Current shared redirects contain an eight-character routing component.
    final dynamic = RegExp(r'^/livestream/dynpath[A-Za-z0-9]{8}/([1-9][0-9]{0,19})/?$').firstMatch(uri.path);
    if (dynamic != null) return dynamic[1];
    // The official hina router declares :id/:antiBlockAlias?. The trailing
    // routing component is never a broadcaster or a second room identity.
    final legacy = RegExp(r'^/hina/livestream/([1-9][0-9]{0,19})(?:/[A-Za-z0-9_-]{1,64})?/?$').firstMatch(uri.path);
    return legacy?[1];
  }

  static Uri? shortUri(String raw) {
    final uri = _webUri(raw);
    if (uri == null || uri.host != 'xhslink.com' || !RegExp(r'^/(?:m/)?[A-Za-z0-9]{1,64}/?$').hasMatch(uri.path)) {
      return null;
    }
    return uri;
  }

  static Future<String?> resolve(String raw, {required LiveShortLinkSession session}) async {
    if (session.isClosed) return null;
    final direct = parse(raw);
    if (direct != null) return direct;
    var current = shortUri(raw);
    while (current != null && !session.isClosed) {
      final response = await session.get(current, headers: XiaohongshuApi.headers);
      if (session.isClosed ||
          response == null ||
          !LiveShortLinkSession.redirectStatuses.contains(response.statusCode)) {
        return null;
      }
      final locations = response.headers['location'];
      if (locations == null || locations.length != 1) return null;
      final location = locations.single.trim();
      // Check spelling before Uri.resolve collapses dot segments/escapes.
      if (location.isEmpty || !_plainPath(location)) return null;
      final Uri target;
      try {
        target = current.resolve(location);
      } on FormatException {
        return null;
      }
      final room = parse(target.toString());
      if (room != null) return room;
      // No arbitrary landing-page, profile, note, other-platform or local fetch.
      current = shortUri(target.toString());
    }
    return null;
  }

  static String url(String roomId) =>
      'https://www.xiaohongshu.com/livestream/${XiaohongshuShare.validateRoomId(roomId)}';
}

// 3.x's xiaohongshu_api.dart (transport injected; the request scope, the
// deadline race and the body reader left out) --------------------------------

typedef XiaohongshuRequest = Future<({int status, String body})> Function(Uri uri, Object? cancel);

/// Current public SSR share page. No dependency on the old login-only share API,
/// no directory discovery or automatic substitution with recommended rooms.
class XiaohongshuApi {
  XiaohongshuApi({required XiaohongshuRequest request}) : _request = request;
  static const origin = 'https://www.xiaohongshu.com';
  static const headers = {
    'Referer': '$origin/',
    'User-Agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/87.0.4280.141 Mobile Safari/537.36',
  };
  final XiaohongshuRequest _request;

  Future<XiaohongshuShare> room(String roomId, {Object? cancel}) async {
    XiaohongshuShare.validateRoomId(roomId);
    try {
      return await _room(roomId, cancel);
    } on StateError {
      rethrow;
    } catch (error) {
      if (error is XiaohongshuException) rethrow;
      throw const XiaohongshuException(XiaohongshuFailure.transport);
    }
  }

  Future<XiaohongshuShare> _room(String roomId, Object? transport) async {
    final response = await _request(Uri.parse('$origin/livestream/$roomId'), transport);
    final failure = switch (response.status) {
      200 => null,
      401 || 403 || 406 => XiaohongshuFailure.access,
      404 => XiaohongshuFailure.missing,
      429 => XiaohongshuFailure.rateLimited,
      >= 500 => XiaohongshuFailure.service,
      _ => XiaohongshuFailure.transport,
    };
    if (failure != null) throw XiaohongshuException(failure);
    return XiaohongshuShare.parsePage(response.body, roomId: roomId);
  }
}

// 3.x's xiaohongshu_site.dart (the directory, which makes no request, left
// out; a fresh short-link session per search as in 3.x) -----------------------

class XiaohongshuSite {
  XiaohongshuSite({required XiaohongshuApi api}) : _api = api;
  final XiaohongshuApi _api;
  String get id => 'xiaohongshu';
  String get name => i18n('site_xiaohongshu');
  String get directoryNoticeKey => 'xiaohongshu_directory_scope';

  String _roomId(String roomId, String platform) {
    if (platform != id) throw const XiaohongshuException(XiaohongshuFailure.identity);
    return XiaohongshuShare.validateRoomId(roomId);
  }

  LiveRoom _room(XiaohongshuShare share, {required bool includeMedia}) => LiveRoom(
    platform: id,
    roomId: share.requestedRoomId,
    // No persistent broadcaster ID contract yet: do not copy the room ID here.
    title: share.title,
    nick: share.nickname,
    avatar: share.avatar,
    cover: share.cover,
    link: XiaohongshuLink.url(share.requestedRoomId),
    liveStatus: switch (share.reportedLive) {
      true => LiveStatus.live,
      false => LiveStatus.offline,
      null => LiveStatus.unknown,
    },
    audienceMetricType: AudienceMetricType.unknown,
    // The legacy LiveRoom default is "0". No measured audience is available;
    // keep card/header counters empty instead of displaying a fabricated zero.
    watching: '',
    notice: [
      i18n('xiaohongshu_room_scope'),
      if (share.access != XiaohongshuAccess.public) i18n('xiaohongshu_restricted'),
      if (share.displayViewers?.isNotEmpty == true)
        i18n('xiaohongshu_display_viewers', args: {'value': share.displayViewers!}),
    ].join('\n'),
    data: includeMedia ? share : null,
  );

  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) async =>
      _room(await _api.room(_roomId(roomId, platform)), includeMedia: true);
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId, required String platform}) async =>
      _room(await _api.room(_roomId(roomId, platform)), includeMedia: false);
  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) async {
    final detail = await getRoomDetail(roomId: roomId, platform: platform);
    if (!detail.isExplicitlyOfflineNow) _snapshot(detail);
    return detail;
  }

  Future<bool> getLiveStatus({required String roomId, required String platform}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId, platform: platform);
    if (room.effectiveLiveStatus == LiveStatus.unknown) throw const XiaohongshuException(XiaohongshuFailure.schema);
    return room.isLiveNow;
  }

  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    if (page != 1) return [];
    final session = LiveShortLinkSession();
    final String? roomId;
    try {
      roomId = await XiaohongshuLink.resolve(keyword, session: session);
    } finally {
      session.close();
    }
    if (roomId == null) return [];
    try {
      return [await getRoomDetailForRefresh(roomId: roomId, platform: id)];
    } on XiaohongshuException catch (error) {
      if (error.kind == XiaohongshuFailure.missing) return [];
      rethrow;
    }
  }

  XiaohongshuShare _snapshot(LiveRoom detail) {
    final roomId = _roomId(detail.roomId ?? '', detail.platform ?? '');
    final data = detail.data;
    if (data is! XiaohongshuShare || data.requestedRoomId != roomId) {
      throw const XiaohongshuException(XiaohongshuFailure.identity);
    }
    if (data.reportedLive == false || detail.isExplicitlyOfflineNow) {
      throw const XiaohongshuException(XiaohongshuFailure.notLive);
    }
    if (data.reportedLive != true || !detail.isLiveNow) {
      throw const XiaohongshuException(XiaohongshuFailure.mediaUnavailable);
    }
    if (data.responseRoomId != roomId) throw const XiaohongshuException(XiaohongshuFailure.identity);
    if (data.access != XiaohongshuAccess.public) throw const XiaohongshuException(XiaohongshuFailure.access);
    if (data.streams.isEmpty) throw const XiaohongshuException(XiaohongshuFailure.mediaUnavailable);
    return data;
  }

  static String _qualityId(XiaohongshuStream stream) => '${stream.codec}:${stream.quality}';
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    _roomId(detail.roomId ?? '', detail.platform ?? '');
    if (detail.isExplicitlyOfflineNow) return [];
    final data = _snapshot(detail);
    final qualities = <String, LivePlayQuality>{};
    for (final source in data.streams) {
      final key = _qualityId(source);
      qualities.putIfAbsent(
        key,
        () => LivePlayQuality(id: key, quality: '${source.label} · ${source.codec.toUpperCase()}'),
      );
    }
    return List.unmodifiable(qualities.values);
  }

  Future<LivePlayUrlResolution> _resolve(LiveRoom detail, LivePlayQuality quality, {required bool refresh}) async {
    var data = _snapshot(detail);
    if (refresh) data = _snapshot(await getRoomDetail(roomId: data.requestedRoomId, platform: id));
    final urls = data.streams
        .where((s) => _qualityId(s) == quality.selectionId.toString())
        .map((s) => s.uri.toString())
        .toList();
    if (urls.isEmpty) throw const XiaohongshuException(XiaohongshuFailure.mediaUnavailable);
    return LivePlayUrlResolution(urls: List.unmodifiable(urls), appliedQualityData: quality.selectionId);
  }

  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) =>
      _resolve(detail, quality, refresh: false);
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => _resolve(detail, quality, refresh: true);
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;
}
