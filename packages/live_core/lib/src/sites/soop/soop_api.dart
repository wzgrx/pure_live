import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/quality_label.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'soop';
const _www = 'https://www.sooplive.co.kr';
const _play = 'https://play.sooplive.co.kr';

/// What the danmaku connection needs to join one room (3.x's
/// `SoopDanmakuArgs`: the endpoint and the chat room number), with the
/// WebSocket headers 3.x built for it (its API headers, `Origin` the player
/// page).
@immutable
final class SoopDanmakuArgs {
  /// Creates the arguments.
  const new({required this.url, required this.plainUrl, required this.chatNo, required this.headers});

  /// `wss://<chat host>:<CHPT + 1>/Websocket/<room id>`: the TLS port next
  /// to the plain one, as the official HTTPS player connects (3.x's URL).
  final Uri url;

  /// `ws://<chat host>:<CHPT>/Websocket/<room id>`: the plain port. The
  /// archived v4 fell back to it where the TLS port was unreachable
  /// (REG-SOOP-002); whether to fall back is the danmaku module's decision
  /// (M5).
  final Uri plainUrl;

  /// `CHATNO`, sent in the join packet.
  final String chatNo;

  /// Handshake headers: 3.x's API headers ([SoopApi.apiHeaders]) with
  /// `Origin: https://play.sooplive.co.kr`, the user's cookie included.
  final Map<String, String> headers;

  @override
  String toString() => 'SoopDanmakuArgs($url, $chatNo)';
}

/// One `VIEWPRESET` entry: the request name of a quality and what the
/// platform says about it.
@immutable
final class SoopPreset {
  /// Creates a preset.
  const new({required this.name, this.bps = 0, this.codec});

  /// Request name (`sd`, `hd`, `hd4k`, `original`, `auto`).
  final String name;

  /// Bitrate in kbps; 0 when not given.
  final int bps;

  /// `avc` or `hevc` from `vcodec`, when known.
  final String? codec;
}

/// The broadcast behind a room, apart from its identity (the streamer id):
/// what the stream requests need. 3.x kept it in `data` as a map (and the
/// broadcast number also in `userId`).
@immutable
final class SoopRoomData {
  /// Creates the data.
  new({
    required this.bno,
    required this.rmd,
    required this.cdn,
    required List<SoopPreset> presets,
    this.password = false,
  }) : presets = List.unmodifiable(presets);

  /// Broadcast number (`BNO`), new with every broadcast.
  final String bno;

  /// Base URL of the stream manager (`RMD`) that assigns playlists.
  final String rmd;

  /// CDN code (`CDN`), also the line id.
  final String cdn;

  /// `VIEWPRESET` in platform order, `auto` included.
  final List<SoopPreset> presets;

  /// `BPWD` is `Y`: the broadcast asks for a password.
  final bool password;

  /// The codec of preset [name], when known.
  String? codecOf(String name) => presets.where((preset) => preset.name == name).firstOrNull?.codec;
}

/// Pure parsing of SOOP (formerly AfreecaTV) responses (3.x's `SoopSite`,
/// with the archived v4 parser's fixes). Each function takes the response
/// text and status and returns 3.x's models or throws a `SiteError`.
abstract final class SoopApi {
  /// Desktop Chrome 128, the UA 3.x sent with every API request.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/128.0.0.0 Safari/537.36';

  /// Desktop Chrome 140, the UA 3.x sent to the media CDN
  /// (`PlaybackHeaderResolver`).
  static const String mediaUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// Web origin: `Origin` and `Referer` of API requests, `Origin` of media
  /// requests.
  static const String origin = _www;

  /// The single first-level category every area is listed under: 3.x's id
  /// and name, so followed areas keep their parent.
  static const ({String id, String name}) category = (id: '1', name: '热门');

  /// Areas asked for per catalog page (3.x's `nListCnt`).
  static const int categoryPageSize = 120;

  /// The room page of streamer [roomId].
  static String roomPageUrl(String roomId) => '$_play/${Uri.encodeComponent(roomId.trim())}';

  /// The headers 3.x sent with every API request (`getHeaders`), names in
  /// lower case; [cookie] only when there is one (3.x sent an empty one).
  static Map<String, String> apiHeaders({String cookie = ''}) => {
    'accept': '*/*',
    'origin': _www,
    'referer': '$_www/',
    'sec-fetch-dest': 'empty',
    'sec-fetch-mode': 'cors',
    'sec-fetch-site': 'same-site',
    'user-agent': userAgent,
    if (cookie.isNotEmpty) 'cookie': cookie,
  };

  /// Media request headers for streamer [roomId] (3.x's
  /// `PlaybackHeaderResolver`): UA, `Origin`, the room page as `Referer`
  /// (the site root without a room) and the user's cookie.
  static Map<String, String> mediaHeaders(String roomId, {String? cookie}) {
    final id = roomId.trim();
    final value = cookie?.trim() ?? '';
    return {
      'user-agent': mediaUserAgent,
      'origin': _www,
      'referer': id.isEmpty ? '$_www/' : roomPageUrl(id),
      if (value.isNotEmpty) 'cookie': value,
    };
  }

  // Catalog -------------------------------------------------------------------

  /// `api.php?m=categoryList`: one page of areas, all under [category], in
  /// platform order (most viewers first). The next page exists while
  /// `is_more` is true; without the flag, while the page is full (3.x's
  /// rule).
  static ({List<LiveArea> areas, bool hasMore}) categoryPage(String body, {int status = 200}) {
    final data = _data(body, status: status, what: 'categoryList');
    final list = _listField(data['list'], body, 'categoryList');
    final areas = [
      for (final raw in list)
        if (_object(raw) case final item? when jsonString(item['category_no']) != null)
          LiveArea(
            platform: _site,
            areaType: category.id,
            typeName: category.name,
            areaId: jsonString(item['category_no'])!,
            areaName: _text(item['category_name']),
            areaPic: normalizeImageUrl(item['cate_img']),
          ),
    ];
    final flag = data['is_more'];
    final more = flag == null ? list.length >= categoryPageSize : _truthy(flag);
    return (areas: areas, hasMore: areas.isNotEmpty && more);
  }

  /// `api.php?m=categoryContentsList`: live rooms of the area named
  /// [areaName] (the area of every card, as in 3.x).
  static List<LiveRoom> areaRooms(String body, {required String areaName, int status = 200}) {
    final data = _data(body, status: status, what: 'categoryContentsList');
    return [
      for (final raw in _listField(data['list'], body, 'categoryContentsList'))
        if (_object(raw) case final item?)
          ?_card(item, cover: item['thumbnail'], avatar: normalizeImageUrl(item['user_profile_img']), area: areaName),
    ];
  }

  /// `main_broad_list_api.php`: live rooms by viewers, 60 a page; the list
  /// ends with an empty page.
  static List<LiveRoom> recommendRooms(String body, {int status = 200}) {
    final root = _root(body, status: status, what: 'main_broad_list');
    return [
      for (final raw in _listField(root['broad'], body, 'main_broad_list'))
        if (_object(raw) case final item?)
          ?_card(item, cover: item['broad_thumb'], area: item['category_name']?.toString()),
    ];
  }

  // Search --------------------------------------------------------------------

  /// `api.php?m=liveSearch`: live rooms matching the keyword (`REAL_BROAD`).
  /// The results end with an empty page: `HAS_MORE_LIST` stays true and
  /// `TOTAL_CNT` non-zero on empty pages (REG-SOOP-007). The area is 3.x's
  /// `standard_broad_cate_name`, which the answers no longer carry, so
  /// search cards have none, as in 3.x (`broad_cate_name` has it; a later
  /// upgrade).
  static List<LiveRoom> searchRooms(String body, {int status = 200}) {
    final root = _root(body, status: status, what: 'liveSearch');
    final result = root['RESULT'];
    if (result != null && jsonInt(result) != 1) {
      throw ApiChanged(_site, 'liveSearch: RESULT $result (${_snippet(body)})');
    }
    return [
      for (final raw in _listField(root['REAL_BROAD'], body, 'liveSearch'))
        if (_object(raw) case final item?)
          ?_card(item, cover: item['broad_img'], area: _text(item['standard_broad_cate_name'])),
    ];
  }

  // Audience ------------------------------------------------------------------

  /// Concurrent viewers of a list entry or `CHANNEL` (3.x's
  /// `parseOnlineViewers`). `total_view_cnt` and `view_cnt` already count
  /// PC and mobile; `current_view_cnt` is PC only and is never used alone
  /// (REG-SOOP-003). Order: the first positive of `total_view_cnt`,
  /// `view_cnt`, `VIEW_CNT`; else the positive sum of `pc_view_cnt` +
  /// `mobile_view_cnt`, then of `current_view_cnt` + `m_current_view_cnt`;
  /// else `0` when any of them said zero; else empty.
  static String onlineViewers(Map<String, dynamic> item) {
    String? zero;
    for (final key in const ['total_view_cnt', 'view_cnt', 'VIEW_CNT']) {
      final text = _text(item[key]).trim();
      if (text.isEmpty || text == 'null' || !RegExp('[0-9]').hasMatch(text)) continue;
      final value = int.tryParse(text.replaceAll(',', '').replaceAll('，', ''));
      if (value == null) continue;
      if (value > 0) return '$value';
      if (value == 0) zero ??= '0';
    }
    for (final (left, right) in const [
      ('pc_view_cnt', 'mobile_view_cnt'),
      ('current_view_cnt', 'm_current_view_cnt'),
    ]) {
      final a = int.tryParse(_text(item[left]).trim().replaceAll(',', ''));
      final b = int.tryParse(_text(item[right]).trim().replaceAll(',', ''));
      if (a == null && b == null) continue;
      final total = (a ?? 0) + (b ?? 0);
      if (total > 0) return '$total';
      zero ??= '0';
    }
    return zero ?? '';
  }

  /// The profile image 3.x showed on recommendation and search cards.
  static String avatar(String roomId) {
    final id = roomId.trim();
    if (id.length < 2) return '';
    return 'https://stimg.sooplive.co.kr/LOGO/${id.substring(0, 2)}/$id/m/$id.webp';
  }

  // Rooms ---------------------------------------------------------------------

  /// `player_live_api.php` (`type=live` or `aid`): `CHANNEL` and its
  /// `RESULT`: 1 broadcasting, 0 not broadcasting (or no such streamer: the
  /// answers are the same), -2 blocked, -6 login required (age-restricted).
  static ({int result, Map<String, dynamic> channel}) channel(String body, {int status = 200}) {
    final root = _root(body, status: status, what: 'player_live_api');
    final channel = _object(root['CHANNEL']);
    if (channel == null) throw ApiChanged(_site, 'player_live_api: no CHANNEL (${_snippet(body)})');
    final result = jsonInt(channel['RESULT']);
    if (result == null) throw ApiChanged(_site, 'player_live_api: no CHANNEL.RESULT (${_snippet(body)})');
    return (result: result, channel: channel);
  }

  /// `player_live_api.php` `type=live`: the room as the user asked for it
  /// ([requestedId]; a follow keeps its identity).
  ///
  /// - `RESULT` 1: live when `VIEWPRESET` is present, else offline (3.x's
  ///   rule); a live broadcast goes into [SoopRoomData], and with
  ///   [withDanmaku] the danmaku arguments carry [cookie].
  /// - 0: offline (an unknown streamer too), -2: banned, as 3.x's refresh
  ///   and recording said. At room entry ([roomEntry]) 3.x reported both as
  ///   a failed load (its page said "获取房间信息失败"), so they are
  ///   `StreamUnavailable` there.
  /// - -6: `NeedsLogin`; anything else `ApiChanged`.
  ///
  /// The cover is the live thumbnail with 3.x's cache buster [now]; the
  /// answer has no audience figure, so the audience is empty.
  static LiveRoom roomDetail(
    String body, {
    required String requestedId,
    required DateTime now,
    String cookie = '',
    bool withDanmaku = false,
    bool roomEntry = false,
    int status = 200,
  }) {
    final answer = channel(body, status: status);
    final id = requestedId.trim();
    switch (answer.result) {
      case 1:
        break;
      case 0 || -2 when roomEntry:
        throw StreamUnavailable(_site, 'player_live_api: RESULT ${answer.result} (not broadcasting or blocked)');
      case 0:
        return LiveRoom(roomId: id, platform: _site, liveStatus: LiveStatus.offline, link: roomPageUrl(id));
      case -2:
        return LiveRoom(roomId: id, platform: _site, liveStatus: LiveStatus.banned, link: roomPageUrl(id));
      case -6:
        throw const NeedsLogin(_site, 'player_live_api: RESULT -6 (age-restricted broadcast)');
      default:
        throw ApiChanged(_site, 'player_live_api: RESULT ${answer.result}');
    }
    final fields = answer.channel;
    final bno = jsonString(fields['BNO']) ?? '';
    final bj = jsonString(fields['BJID']) ?? id;
    final tags = fields['CATEGORY_TAGS'];
    final live = fields['VIEWPRESET'] != null;
    final viewers = onlineViewers(fields);
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: _text(fields['TITLE']),
      nick: _text(fields['BJNICK']),
      avatar: bj.length < 2 ? '' : 'https://stimg.sooplive.co.kr/LOGO/${bj.substring(0, 2)}/$bj/$bj.jpg',
      cover: bno.isEmpty ? '' : 'https://liveimg.sooplive.co.kr/m/$bno?_t=${now.millisecondsSinceEpoch}',
      area: tags is List && tags.isNotEmpty ? _text(tags.first) : '',
      watching: viewers,
      onlineViewers: viewers,
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
      link: roomPageUrl(id),
      introduction: '',
      notice: '',
      data: live
          ? SoopRoomData(
              bno: bno,
              rmd: _text(fields['RMD']).trim(),
              cdn: _text(fields['CDN']).trim(),
              presets: presets(fields['VIEWPRESET']),
              password: jsonString(fields['BPWD'])?.toUpperCase() == 'Y',
            )
          : null,
      danmakuData: withDanmaku ? danmakuArgs(fields, roomId: id, cookie: cookie) : null,
    );
  }

  /// `VIEWPRESET` entries with a name, in platform order.
  static List<SoopPreset> presets(Object? value) => [
    for (final raw in _list(value))
      if (_object(raw) case final item? when _text(item['name']).trim().isNotEmpty)
        SoopPreset(
          name: _text(item['name']).trim(),
          bps: int.tryParse(_text(item['bps']).trim()) ?? 0,
          codec: switch (_text(item['vcodec']).trim().toLowerCase()) {
            'h264' || 'avc' => 'avc',
            'h265' || 'hevc' => 'hevc',
            _ => null,
          },
        ),
  ];

  /// The danmaku arguments of a `CHANNEL` for streamer [roomId]
  /// (3.x's `buildDanmakuWebSocketUrl`): the chat host is `CHDOMAIN`, else
  /// `chat-<CHIP as hex>.sooplive.co.kr`, and the TLS port is `CHPT + 1`.
  /// Null without `CHATNO`, a host or a plain port below 65535 (3.x
  /// connected nothing then).
  static SoopDanmakuArgs? danmakuArgs(Map<String, dynamic> channel, {required String roomId, String cookie = ''}) {
    final id = roomId.trim();
    final chatNo = _text(channel['CHATNO']).trim();
    final host = jsonString(channel['CHDOMAIN']) ?? _chatHost(_text(channel['CHIP']).trim());
    final port = jsonInt(channel['CHPT']);
    if (id.isEmpty || chatNo.isEmpty || host == null || port == null || port <= 0 || port >= 65535) return null;
    return SoopDanmakuArgs(
      url: Uri(scheme: 'wss', host: host, port: port + 1, pathSegments: ['Websocket', id]),
      plainUrl: Uri(scheme: 'ws', host: host, port: port, pathSegments: ['Websocket', id]),
      chatNo: chatNo,
      headers: {
        ...apiHeaders(cookie: cookie),
        'origin': _play,
      },
    );
  }

  /// `chat-<IPv4 as eight hex digits>.sooplive.co.kr` (3.x), or null. The
  /// chat hosts the API names (`CHDOMAIN`) are on `sooplive.com`; the
  /// archived v4 used that domain here, a later upgrade.
  static String? _chatHost(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null || part < 0 || part > 255)) return null;
    return 'chat-${parts.map((part) => part!.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}.sooplive.co.kr';
  }

  // Streams -------------------------------------------------------------------

  /// Qualities of [presets] (3.x's `getPlayQualites`): `auto` and nameless
  /// entries left out, one per name (case ignored, the first wins), the
  /// request name as id, best first by [qualitySort].
  static List<LivePlayQuality> qualities(List<SoopPreset> presets) {
    final seen = <String>{};
    final options = <LivePlayQuality>[];
    for (final preset in presets) {
      final key = preset.name.toLowerCase();
      if (key == 'auto' || !seen.add(key)) continue;
      options.add(
        LivePlayQuality(
          quality: LiveQualityLabel.normalize(
            platform: _site,
            rawLabel: preset.name,
            id: preset.name,
            bitrate: preset.bps > 0 ? preset.bps : null,
          ),
          id: preset.name,
          sort: qualitySort(preset.name, preset.bps),
          data: const <String>[],
        ),
      );
    }
    final ordered = options.indexed.toList()
      ..sort((a, b) {
        final bySort = b.$2.sort.compareTo(a.$2.sort);
        return bySort != 0 ? bySort : a.$1.compareTo(b.$1);
      });
    return [for (final (_, quality) in ordered) quality];
  }

  /// The order of a preset (3.x's `_qualitySort`): the name's tier first,
  /// the bitrate within it, so a source without a bitrate never falls
  /// below a transcode (REG-SOOP-004). Tiers: `original` > `master` >
  /// `fullhd` > `hd` > `sd` > `low`; other names rank by bitrate alone,
  /// below every tier. That includes the 720p preset `hd4k`, which 3.x
  /// listed last under its request name; giving it a tier (and the name
  /// “超清”) is a later upgrade.
  static int qualitySort(String name, int bps) {
    final rank = switch (name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '')) {
      'original' || 'origin' || 'source' => 6,
      'master' || 'uhd' => 5,
      'fullhd' || 'fhd' => 4,
      'hd' => 3,
      'sd' || 'normal' => 2,
      'low' || 'ld' => 1,
      _ => 0,
    };
    return rank == 0 ? bps : rank * 100000000 + bps.clamp(0, 99999999);
  }

  /// The `return_type` of the stream assignment for CDN code [cdn].
  static String returnType(String cdn) {
    if (cdn.contains('gs_cdn')) return 'gs_cdn_pc_web';
    if (cdn.contains('lg_cdn')) return 'lg_cdn_pc_web';
    return cdn;
  }

  /// `<RMD>/broad_stream_assign.html` for preset [quality] of broadcast
  /// [bno] (RMD's own path kept, a trailing `/` dropped).
  static Uri assignUrl({required String rmd, required String cdn, required String bno, required String quality}) {
    final base = Uri.tryParse('${rmd.replaceAll(RegExp(r'/$'), '')}/broad_stream_assign.html');
    if (base == null || !(base.isScheme('http') || base.isScheme('https')) || base.host.isEmpty) {
      throw ApiChanged(_site, 'player_live_api: RMD "$rmd" is not a URL');
    }
    return base.replace(queryParameters: {'return_type': returnType(cdn), 'broad_key': '$bno-common-$quality-hls'});
  }

  /// `broad_stream_assign.html`: the playlist URL (`view_url`). A `result`
  /// other than 1 is `StreamUnavailable`; 1 without a URL `ApiChanged`.
  static String assignedPlaylist(String body, {int status = 200}) {
    final root = _root(body, status: status, what: 'broad_stream_assign');
    final result = jsonInt(root['result']);
    if (result != 1) throw StreamUnavailable(_site, 'broad_stream_assign: result ${root['result']}');
    final url = jsonUrl(root['view_url']);
    if (url == null) throw ApiChanged(_site, 'broad_stream_assign: no view_url (${_snippet(body)})');
    return jsonString(root['view_url'])!;
  }

  /// `player_live_api.php` `type=aid`: the stream key. -6 is `NeedsLogin`
  /// (age-restricted); any other answer without a key `StreamUnavailable`
  /// (3.x got an empty key and no URL), noting a [password] broadcast.
  static String aid(String body, {int status = 200, bool password = false}) {
    final answer = channel(body, status: status);
    if (answer.result == -6) throw const NeedsLogin(_site, 'aid: RESULT -6 (age-restricted broadcast)');
    final aid = jsonString(answer.channel['AID']);
    if (answer.result != 1 || aid == null) {
      throw StreamUnavailable(_site, 'aid: RESULT ${answer.result}${password ? ', password-protected' : ''}');
    }
    return aid;
  }

  /// The line of [playlist] with stream key [aid] (3.x's
  /// `'$view_url?aid=$aid'`) for streamer [roomId] at preset [quality]: the
  /// media headers with [cookie], HLS, [codec], the CDN code as line id and
  /// no lease (a playlist with its key keeps working; recovery asks
  /// again). The platform does not say which quality it applied; the
  /// requested one is assumed, as 3.x did.
  static LivePlayUrlResolution resolution({
    required String playlist,
    required String aid,
    required String roomId,
    required String quality,
    required String cdn,
    String? codec,
    String? cookie,
  }) {
    final url = '$playlist${playlist.contains('?') ? '&' : '?'}aid=$aid';
    final uri = Uri.parse(url);
    return LivePlayUrlResolution.lines([
      LivePlayLine(
        url,
        headers: mediaHeaders(roomId, cookie: cookie),
        format: uri.path.toLowerCase().endsWith('.flv') ? StreamFormat.flv : StreamFormat.hls,
        codec: codec,
        lineId: cdn.isEmpty ? uri.host : cdn,
      ),
    ], appliedQualityData: quality);
  }

  // Helpers -------------------------------------------------------------------

  /// A list card: live, the audience from [onlineViewers], the avatar
  /// [avatar] or the one built from the id. Null without `user_id`.
  static LiveRoom? _card(Map<String, dynamic> item, {required Object? cover, String avatar = '', String? area}) {
    final id = jsonString(item['user_id']);
    if (id == null) return null;
    final viewers = onlineViewers(item);
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: _text(item['broad_title']),
      nick: _text(item['user_nick']),
      avatar: avatar.isEmpty ? SoopApi.avatar(id) : avatar,
      cover: normalizeImageUrl(cover),
      area: area,
      watching: viewers,
      onlineViewers: viewers,
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: LiveStatus.live,
    );
  }
}

/// A field as 3.x wrote it (`toString()`), empty when missing (3.x wrote
/// "null" or threw).
String _text(Object? value) => value == null ? '' : '$value';

bool _truthy(Object? value) => value == true || value == 1 || (value is String && value.trim().toLowerCase() == 'true');

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

/// A list field: missing is empty, anything else but a list `ApiChanged`.
List<Object?> _listField(Object? value, String body, String what) {
  if (value == null) return const [];
  if (value is! List) throw ApiChanged(_site, '$what: the list is not a list (${_snippet(body)})');
  return value.cast<Object?>();
}

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// The JSON object of an answer (the player API and the stream manager
/// answer JSON as `text/html`). HTTP 429 → `RateLimited`; 5xx →
/// `NetworkFailure`; 401 and 403 → `RiskControl`; any other non-2xx or a
/// body that is not an object → `ApiChanged`.
Map<String, dynamic> _root(String body, {required int status, required String what}) {
  if (status == 429) throw RateLimited(_site, detail: '$what: HTTP 429');
  if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
  if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what: HTTP $status');
  if (status < 200 || status >= 300) throw ApiChanged(_site, '$what: HTTP $status (${_snippet(body)})');
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not a JSON object (${_snippet(body)})');
  return decoded;
}

/// `data` of an `api.php` answer (`{"result": 1, "data": {…}}`); a `result`
/// other than 1 is `ApiChanged`.
Map<String, dynamic> _data(String body, {required int status, required String what}) {
  final root = _root(body, status: status, what: what);
  final result = root['result'];
  if (result != null && jsonInt(result) != 1) throw ApiChanged(_site, '$what: result $result (${_snippet(body)})');
  final data = _object(root['data']);
  if (data == null) throw ApiChanged(_site, '$what: no data object (${_snippet(body)})');
  return data;
}
