import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/html.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'xiaohongshu';
const _web = 'https://www.xiaohongshu.com';

/// Whether a room can be watched without conditions (3.x's
/// `XiaohongshuAccess`).
enum XiaohongshuAccess {
  /// `monetizeType` 0 and no `joinLimitTypes` entry other than 0.
  public,

  /// Paid (`monetizeType` other than 0) or limited (family, group, region,
  /// or a limit not known yet): no public full stream.
  restricted,

  /// `monetizeType` or `joinLimitTypes` is missing: not known to be public.
  unknown,
}

/// What a room's share page said beyond its card: 3.x kept this snapshot in
/// `data` on room entry and read the stream from it.
///
/// The stream is kept as answered (`pullConfig`) and checked only when it
/// is played ([XiaohongshuApi.playable]): 3.x checked it while reading the
/// page, so one malformed pull address failed the room page and the follow
/// refresh too.
@immutable
final class XiaohongshuRoomData {
  /// Creates the data.
  const new({required this.roomId, required this.live, required this.access, this.pullConfig, this.displayViewers});

  /// The room id that was asked for; a live page named the same room.
  final String roomId;

  /// `roomInfo.status`: 2 → true (live), 3 → false (ended), anything else
  /// null (not known).
  final bool? live;

  /// Whether the room is public.
  final XiaohongshuAccess access;

  /// `roomInfo.pullConfig` as answered (a JSON string), kept only for a
  /// live public room, as 3.x read it only then; null otherwise.
  final Object? pullConfig;

  /// `roomInfo.displayViewerCount`: the platform's display text ("300万+"),
  /// not a measured audience.
  final String? displayViewers;
}

/// One pull address of `pullConfig` (3.x's `XiaohongshuStream`).
@immutable
final class XiaohongshuStream {
  /// Creates the address.
  const new({required this.url, required this.codec, required this.quality, required this.label});

  /// The address, on `*.xhscdn.com` under `/live/<room>.flv` or `.m3u8`.
  final Uri url;

  /// `h264` or `h265`, the list it was in.
  final String codec;

  /// `quality_type` (`HD`).
  final String quality;

  /// `quality_type_name` (`原画`).
  final String label;

  /// HLS for a `.m3u8` path, else FLV.
  StreamFormat get format => url.path.endsWith('.m3u8') ? StreamFormat.hls : StreamFormat.flv;

  /// The quality id 3.x gave it: codec and quality (`h264:HD`).
  String get qualityId => '$codec:$quality';
}

/// A room's share page: the room (without `data` attached) and its data.
typedef XiaohongshuPage = ({LiveRoom room, XiaohongshuRoomData data});

/// Pure parsing of Xiaohongshu (3.x's `XiaohongshuShare`, `XiaohongshuLink`
/// and the page request of `XiaohongshuApi`). There is no directory, keyword
/// search or danmaku: a room is the public share page
/// `www.xiaohongshu.com/livestream/<room>`, whose hydration state holds the
/// card, the state and the pull addresses. Each function takes the response
/// text and status and returns 3.x's models or throws a `SiteError`.
///
/// Room ids are broadcast rooms: a streamer gets a new one every time they
/// go live, and 3.x follows the room, not the streamer.
abstract final class XiaohongshuApi {
  /// Web origin: the share pages, and `Referer` with a trailing slash.
  static const String origin = _web;

  /// The Android Chrome UA 3.x sent (`XiaohongshuApi.headers`).
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/87.0.4280.141 Mobile Safari/537.36';

  /// What 3.x sent with the page, short-link and media requests
  /// (`XiaohongshuApi.headers`, which its `PlaybackHeaderResolver` also
  /// used), names in lower case; no cookie.
  static const Map<String, String> headers = {'referer': '$_web/', 'user-agent': userAgent};

  /// Largest page 3.x accepted (2 MiB); a larger one is `ApiChanged`.
  static const int responseLimit = 2 * 1024 * 1024;

  /// A broadcast room id: 1–20 digits without a leading zero.
  static final RegExp roomIdPattern = RegExp(r'^[1-9][0-9]{0,19}$');

  /// The first line of every room's notice (3.x's zh.json
  /// `xiaohongshu_room_scope`); the interface may show its own translation.
  static const String roomScopeNotice = '当前以直播房间号跟踪；主播重新开播使用新房间号时，请重新导入分享链接。';

  /// The notice line of a room that is not public (zh.json
  /// `xiaohongshu_restricted`).
  static const String restrictedNotice = '该房间存在访问条件或访问状态待确认，当前没有可用的公开完整直播源。';

  /// The explanation 3.x showed on the empty directory (zh.json
  /// `xiaohongshu_directory_scope`, the directory notice key's text).
  static const String directoryScope = '暂无已接入的公开直播目录。请在搜索页输入直播房间号，或导入官网 /livestream/ 分享链接；收藏仅跟踪该直播房间，不代表跨场次跟随主播。';

  /// The notice line with the platform's display count (zh.json
  /// `xiaohongshu_display_viewers`).
  static String displayViewersNotice(String value) => '平台展示观看值：$value（非已验证的实时在线人数）';

  /// Whether [id] is a broadcast room id.
  static bool isRoomId(String id) => roomIdPattern.hasMatch(id);

  /// The share page of [roomId], also the room's link.
  static Uri roomUrl(String roomId) => Uri.parse('$_web/livestream/$roomId');

  // Share page ----------------------------------------------------------------

  /// The share page of [requestedId] (a room id), answered with [status].
  ///
  /// - Status: only 200 is a page; 401, 403 and 406 are `RiskControl`
  ///   (3.x's "access"), 404 `NotFound`, 429 `RateLimited`, 5xx and any
  ///   other status (a redirect: the page must be the one asked for)
  ///   `NetworkFailure` (3.x's "service" and "transport").
  /// - `liveStream.pageStatus` "error" ("未找到直播间，请稍后再试") is
  ///   `NotFound`; 3.x called it an unexplained page error.
  /// - The page's own `roomId`, when present, must be the one asked for; a
  ///   live page must have it. An ended page has none and may recommend
  ///   another live room in `nextRoomInfo`, which is never read.
  /// - `status` 2 with `liveStatus` "success" is live, 3 with "end" ended;
  ///   another status is not known (the room is shown as such, as in 3.x),
  ///   and a status that contradicts `liveStatus` is `ApiChanged`.
  /// - 3.x read `status`, `monetizeType` and `joinLimitTypes` as JSON
  ///   integers and a list; the same values written as strings (`"2"`,
  ///   `"[0]"`, recorded by the archived spec) are accepted too.
  ///
  /// The room's id is [requestedId] (3.x); it has no streamer id, no
  /// audience (`displayViewerCount` is display text, in the notice) and the
  /// notice 3.x wrote.
  static XiaohongshuPage room(String body, {required String requestedId, required int status}) {
    if (!isRoomId(requestedId)) throw ArgumentError.value(requestedId, 'requestedId', 'not a Xiaohongshu room id');
    _checkStatus(status);
    final state = _liveStream(body);
    final page = state['pageStatus'];
    if (page == 'error') {
      throw NotFound(_site, 'share page $requestedId: ${jsonString(state['errorMessage']) ?? 'pageStatus error'}');
    }
    if (page != 'success') throw ApiChanged(_site, 'share page: pageStatus ${jsonEncode(page)}');
    final data = _object(state['roomData'], 'roomData');
    final info = _object(data['roomInfo'], 'roomInfo');
    final host = _object(data['hostInfo'], 'hostInfo');
    final responseId = info['roomId'];
    if (responseId != null && (responseId is! String || responseId != requestedId)) {
      throw ApiChanged(_site, 'share page: asked for $requestedId, got ${jsonEncode(responseId)}');
    }
    final code = _count(info['status']);
    if (code == null) throw ApiChanged(_site, 'share page: status ${jsonEncode(info['status'])}');
    final liveStatus = state['liveStatus'];
    final live = switch (code) {
      2 => true,
      3 => false,
      _ => null,
    };
    if ((live == true && liveStatus != 'success') || (live == false && liveStatus != 'end')) {
      throw ApiChanged(_site, 'share page: status $code with liveStatus ${jsonEncode(liveStatus)}');
    }
    if (live == true && responseId == null) throw const ApiChanged(_site, 'share page: live without roomId');
    final access = _access(info['monetizeType'], info['joinLimitTypes']);
    final title = _text(info['roomTitle'], 'roomTitle');
    final nick = _text(host['nickName'], 'nickName');
    final cover = _text(info['roomCover'], 'roomCover');
    final avatar = _text(host['avatar'], 'avatar');
    final roomData = XiaohongshuRoomData(
      roomId: requestedId,
      live: live,
      access: access,
      pullConfig: live == true && access == XiaohongshuAccess.public ? info['pullConfig'] : null,
      displayViewers: _text(info['displayViewerCount'], 'displayViewerCount'),
    );
    return (
      room: LiveRoom(
        roomId: requestedId,
        platform: _site,
        link: roomUrl(requestedId).toString(),
        title: title ?? '',
        nick: nick ?? '',
        avatar: normalizeImageUrl(avatar),
        cover: normalizeImageUrl(cover),
        watching: '',
        audienceMetricType: AudienceMetricType.unknown,
        liveStatus: switch (live) {
          true => LiveStatus.live,
          false => LiveStatus.offline,
          null => LiveStatus.unknown,
        },
        notice: notice(roomData),
      ),
      data: roomData,
    );
  }

  /// 3.x's notice: the room-scope line, the restriction line for a room
  /// that is not public, and the display count when the page had one.
  static String notice(XiaohongshuRoomData data) => [
    roomScopeNotice,
    if (data.access != XiaohongshuAccess.public) restrictedNotice,
    if (data.displayViewers case final String value when value.isNotEmpty) displayViewersNotice(value),
  ].join('\n');

  /// `liveStream` of the one `<script>` whose text starts with
  /// `window.__INITIAL_STATE__=`, as 3.x found it; bare `undefined` outside
  /// strings becomes `null` and nothing else of JavaScript is accepted.
  static Map<String, dynamic> _liveStream(String page) {
    const marker = 'window.__INITIAL_STATE__=';
    if (page.length > responseLimit || (page.length > responseLimit ~/ 3 && utf8.encode(page).length > responseLimit)) {
      throw const ApiChanged(_site, 'share page: over $responseLimit bytes');
    }
    final scripts = HtmlElement.parseFragment(page)
        .queryAll((element) => element.tag == 'script' && element.text.trimLeft().startsWith(marker))
        .toList();
    if (scripts.length != 1) throw ApiChanged(_site, 'share page: ${scripts.length} hydration scripts');
    var source = scripts.single.text.trim().substring(marker.length).trim();
    if (source.endsWith(';')) source = source.substring(0, source.length - 1).trimRight();
    final Object? decoded;
    try {
      decoded = jsonDecode(_hydrationJson(source));
    } on FormatException {
      throw const ApiChanged(_site, 'share page: hydration state is not JSON');
    }
    return _object(_object(decoded, 'hydration state')['liveStream'], 'liveStream');
  }

  /// [source] with every bare `undefined` token outside strings written as
  /// `null` (3.x's scanner): a global replace would corrupt titles and URLs
  /// holding the word, and `jsonDecode` still rejects anything else.
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

  /// 3.x's access rule; a value of the wrong shape is `ApiChanged`.
  static XiaohongshuAccess _access(Object? monetization, Object? limits) {
    final paid = _count(monetization);
    if (monetization != null && paid == null) {
      throw ApiChanged(_site, 'share page: monetizeType ${jsonEncode(monetization)}');
    }
    final list = limits is String ? _decodeOrNull(limits) : limits;
    final kinds = list is List && list.length <= 16 ? [for (final value in list) _count(value)] : null;
    if (limits != null && (kinds == null || kinds.contains(null))) {
      throw ApiChanged(_site, 'share page: joinLimitTypes ${jsonEncode(limits)}');
    }
    if (paid == null || kinds == null) return XiaohongshuAccess.unknown;
    return paid != 0 || kinds.any((kind) => kind != 0) ? XiaohongshuAccess.restricted : XiaohongshuAccess.public;
  }

  // Streams -------------------------------------------------------------------

  /// The pull addresses of a room that can be played, checked as 3.x did
  /// before playing (`_snapshot`): an ended room or one whose state is not
  /// known is `StreamUnavailable`, a room that is not public `NeedsLogin`
  /// (paid or limited; 3.x had no Xiaohongshu account), no address
  /// `StreamUnavailable`, and a malformed `pullConfig` `ApiChanged`.
  static List<XiaohongshuStream> playable(XiaohongshuRoomData data) {
    if (data.live == false) throw StreamUnavailable(_site, 'room ${data.roomId} has ended');
    if (data.live != true) throw StreamUnavailable(_site, 'room ${data.roomId}: state not known');
    if (data.access != XiaohongshuAccess.public) {
      throw NeedsLogin(_site, 'room ${data.roomId} is ${data.access.name}');
    }
    final streams = _streams(data.pullConfig, data.roomId);
    if (streams.isEmpty) throw StreamUnavailable(_site, 'room ${data.roomId}: no pull address');
    return streams;
  }

  /// 3.x's `pullConfig` rules: the `h264` rows, then the `h265` rows, at
  /// most 32 each; every row has an address, a quality and a label; the
  /// address is http(s) on the default port, on a subdomain of
  /// `xhscdn.com`, without user or fragment, at `/live/<room>.m3u8` or
  /// `.flv`; the same codec, quality and address once. Any other shape is
  /// `ApiChanged`. The JSON string 3.x read may also be the object itself.
  static List<XiaohongshuStream> _streams(Object? value, String roomId) {
    if (value == null || value == '') return const [];
    final Object? decoded;
    if (value is String) {
      if (value.length > 65536) throw const ApiChanged(_site, 'pullConfig: over 65536 characters');
      decoded = _decodeOrNull(value);
    } else {
      decoded = value;
    }
    final config = _object(decoded, 'pullConfig');
    final result = <XiaohongshuStream>[];
    final seen = <String>{};
    for (final codec in const ['h264', 'h265']) {
      final rows = config[codec];
      if (rows == null) continue;
      if (rows is! List || rows.length > 32) throw ApiChanged(_site, 'pullConfig: $codec is not a list of at most 32');
      for (final value in rows) {
        final row = _object(value, 'pullConfig.$codec[]');
        final url = _text(row['master_url'], 'master_url');
        final quality = _text(row['quality_type'], 'quality_type', limit: 64);
        final label = _text(row['quality_type_name'], 'quality_type_name', limit: 128);
        if (url == null || quality == null || quality.isEmpty || label == null || label.isEmpty) {
          throw ApiChanged(_site, 'pullConfig: incomplete $codec row');
        }
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !(uri.scheme == 'http' || uri.scheme == 'https') ||
            !(uri.host.endsWith('.xhscdn.com') && uri.host != '.xhscdn.com') ||
            uri.userInfo.isNotEmpty ||
            uri.hasFragment ||
            uri.port != (uri.scheme == 'https' ? 443 : 80) ||
            !(uri.path == '/live/$roomId.m3u8' || uri.path == '/live/$roomId.flv')) {
          throw ApiChanged(_site, 'pullConfig: address outside room $roomId: $url');
        }
        if (seen.add('$codec|$quality|$uri')) {
          result.add(XiaohongshuStream(url: uri, codec: codec, quality: quality, label: label));
        }
      }
    }
    return List.unmodifiable(result);
  }

  /// 3.x's qualities: one per codec and quality, in address order, named
  /// `原画 · H264`, with the id `h264:HD`.
  static List<LivePlayQuality> qualities(List<XiaohongshuStream> streams) {
    final qualities = <String, LivePlayQuality>{};
    for (final stream in streams) {
      qualities.putIfAbsent(
        stream.qualityId,
        () => LivePlayQuality(quality: '${stream.label} · ${stream.codec.toUpperCase()}', id: stream.qualityId),
      );
    }
    return List.unmodifiable(qualities.values);
  }

  /// Every address of [quality] as a line, in the page's order (3.x: HLS
  /// first on the recorded page), with [headers] and no lease (the
  /// addresses are not signed). A quality the room no longer has is
  /// `StreamUnavailable`.
  static LivePlayUrlResolution resolution(List<XiaohongshuStream> streams, LivePlayQuality quality) {
    final id = '${quality.selectionId}';
    final lines = [
      for (final stream in streams)
        if (stream.qualityId == id)
          LivePlayLine(
            stream.url.toString(),
            headers: headers,
            format: stream.format,
            codec: stream.codec == 'h265' ? 'hevc' : 'avc',
            lineId: '${stream.format.name}:${stream.url.host.split('.').first}',
          ),
    ];
    if (lines.isEmpty) throw StreamUnavailable(_site, 'no address for quality $id');
    return LivePlayUrlResolution.lines(lines, appliedQualityData: quality.selectionId);
  }

  // Links ---------------------------------------------------------------------

  static final RegExp _deepLinks = RegExp(
    r'(?<![A-Za-z0-9:/=?&._-])xhsdiscover://live_audience\?[^\s<>]+',
    caseSensitive: false,
  );
  static final RegExp _chineseProse = RegExp('[，。！？、；：）》」』”’]');
  static final RegExp _controls = RegExp(r'[\x00-\x20\x7f]');
  static final RegExp _canonicalPath = RegExp(r'^/livestream/([1-9][0-9]{0,19})/?$');
  static final RegExp _dynamicPath = RegExp(r'^/livestream/dynpath[A-Za-z0-9]{8}/([1-9][0-9]{0,19})/?$');
  static final RegExp _hinaPath = RegExp(r'^/hina/livestream/([1-9][0-9]{0,19})(?:/[A-Za-z0-9_-]{1,64})?/?$');
  static final RegExp _shortPath = RegExp(r'^/(?:m/)?[A-Za-z0-9]{1,64}/?$');

  /// The room [raw] names without a request (3.x's `XiaohongshuLink.parse`):
  /// a bare room id, an app deep link ([deepLinkRoomId]) or a share page
  /// ([webRoomId]); null otherwise.
  static String? roomIdFrom(String raw) {
    final value = raw.trim();
    if (isRoomId(value)) return value;
    return deepLinkRoomId(value) ?? webRoomId(value);
  }

  /// The room of an app deep link `xhsdiscover://live_audience?room_id=…
  /// &source=…`: exactly one `room_id` and one non-empty `source`, no path,
  /// user, port or fragment (3.x). Its `flvUrl` is only a preload hint.
  static String? deepLinkRoomId(String raw) {
    final value = raw.trim();
    if (value.length > 8192 || value.contains(_controls)) return null;
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
      if (room == null || room.length != 1 || source == null || source.length != 1 || source.single.trim().isEmpty) {
        return null;
      }
      return isRoomId(room.single) ? room.single : null;
    } on FormatException {
      return null;
    }
  }

  /// The room of a share page on `www.xiaohongshu.com` or `xiaohongshu.com`
  /// (3.x): `/livestream/<room>`, `/livestream/dynpath<8>/<room>` (the
  /// share redirect) or `/hina/livestream/<room>[/<alias>]`, http(s) on the
  /// default port, without user, escapes, backslashes or dot segments in the
  /// path as written.
  static String? webRoomId(String raw) {
    final uri = _webUri(raw);
    if (uri == null || !(uri.host == 'www.xiaohongshu.com' || uri.host == 'xiaohongshu.com')) return null;
    return (_canonicalPath.firstMatch(uri.path) ?? _dynamicPath.firstMatch(uri.path) ?? _hinaPath.firstMatch(uri.path))
        ?.group(1);
  }

  /// A short link `xhslink.com/<code>` or `xhslink.com/m/<code>` (3.x's
  /// `shortUri`), else null.
  static Uri? shortLink(String raw) {
    final uri = _webUri(raw);
    return uri != null && uri.host == 'xhslink.com' && _shortPath.hasMatch(uri.path) ? uri : null;
  }

  /// Where one short-link hop from [current] leads (3.x's `resolve`): a
  /// redirect [status] with exactly one non-empty `Location` whose path, as
  /// written, has no escapes, backslashes or dot segments; null otherwise.
  static Uri? shortLinkHop(Uri current, {required int status, List<String>? locations}) {
    if (!const {301, 302, 303, 307, 308}.contains(status) || locations == null || locations.length != 1) return null;
    final location = locations.single.trim();
    if (location.isEmpty || !_plainPath(location)) return null;
    try {
      return current.resolve(location);
    } on FormatException {
      return null;
    }
  }

  /// The rooms of the app deep links in a share text, in order (3.x's
  /// `_sharedXhsDeepLinks`): a deep link not glued to a preceding URL, cut
  /// at the first Chinese punctuation mark and trailing ASCII punctuation.
  static Iterable<String> shareTextRoomIds(String text) sync* {
    for (final match in _deepLinks.allMatches(text)) {
      final candidate = match.group(0)!.split(_chineseProse).first.replaceFirst(RegExp(r'''[,!?;:)\]}"']+$'''), '');
      final roomId = deepLinkRoomId(candidate);
      if (roomId != null) yield roomId;
    }
  }

  static bool _plainPath(String value) {
    if (value.length > 8192 || value.contains(_controls)) return false;
    final path = value.split(RegExp('[?#]')).first;
    return !path.contains('%') && !path.contains(r'\') && !RegExp(r'(^|/)\.\.?(/|$)').hasMatch(path);
  }

  static Uri? _webUri(String raw) {
    final value = raw.trim();
    if (!_plainPath(value)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80))) {
      return null;
    }
    return uri;
  }

  // Helpers -------------------------------------------------------------------

  /// 3.x's status rules (see [room]).
  static void _checkStatus(int status) {
    if (status == 200) return;
    throw switch (status) {
      401 || 403 || 406 => RiskControl(_site, detail: 'share page: HTTP $status'),
      404 => const NotFound(_site, 'share page: HTTP 404'),
      429 => const RateLimited(_site, detail: 'share page: HTTP 429'),
      _ => NetworkFailure(_site, 'share page: HTTP $status'),
    };
  }

  static Map<String, dynamic> _object(Object? value, String what) {
    if (value is! Map<String, dynamic>) throw ApiChanged(_site, 'share page: $what is not an object');
    return value;
  }

  /// A string of at most [limit] characters, or null when absent; anything
  /// else is `ApiChanged` (3.x).
  static String? _text(Object? value, String what, {int limit = 4096}) {
    if (value == null) return null;
    if (value is! String || value.length > limit) throw ApiChanged(_site, 'share page: $what is not a short text');
    return value;
  }

  /// A count 3.x read as a JSON integer of zero or more; the same integer
  /// written as a string is accepted too.
  static int? _count(Object? value) => switch (value) {
    final int count when count >= 0 => count,
    final String text when RegExp(r'^\d{1,9}$').hasMatch(text.trim()) => int.parse(text.trim()),
    _ => null,
  };

  static Object? _decodeOrNull(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
