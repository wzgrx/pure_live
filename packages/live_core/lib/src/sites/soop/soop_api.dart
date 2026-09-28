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
const _appScheme = 'sooplive';

/// Korea Standard Time, the zone of every `broad_start` (no daylight saving).
const _kst = Duration(hours: 9);

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

/// A streamer's station (`chapi.sooplive.co.kr/api/<id>/station`), read at
/// room entry (7-5): the profile the player API lacks and, while one is on,
/// the broadcast.
@immutable
final class SoopStation {
  /// Creates the station.
  const new({this.nick = '', this.avatar = '', this.introduction = '', this.broadcast});

  /// `station.user_nick`, entities decoded.
  final String nick;

  /// `profile_image`: the profile picture the streamer set.
  final String avatar;

  /// `station.station_title`, the station's tagline.
  final String introduction;

  /// `broad` while broadcasting; null when not.
  final SoopStationBroadcast? broadcast;
}

/// The broadcast a station names (`broad`).
@immutable
final class SoopStationBroadcast {
  /// Creates the broadcast.
  const new({
    required this.bno,
    this.title = '',
    this.viewers = '',
    this.startedAt,
    this.restriction = LiveRestriction.none,
  });

  /// `broad_no`.
  final String bno;

  /// `broad_title`, entities decoded.
  final String title;

  /// `current_sum_viewer`: viewers now, PC and mobile.
  final String viewers;

  /// `station.broad_start` (Korean time) in UTC.
  final DateTime? startedAt;

  /// From `is_password`, `subscription_only` and `broad_grade`.
  final LiveRestriction restriction;
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

  /// The SOOP app's link to streamer [roomId]'s broadcast [bno] (7-9), as
  /// list entries carry it (`scheme`, S02):
  /// `sooplive://player/live?broad_no=<bno>&user_id=<id>`; without [bno]
  /// only `user_id`.
  static String appLink(String roomId, {String bno = ''}) => Uri(
    scheme: _appScheme,
    host: 'player',
    path: '/live',
    queryParameters: {if (bno.trim().isNotEmpty) 'broad_no': bno.trim(), 'user_id': roomId.trim()},
  ).toString();

  /// The streamer of a SOOP app link ([appLink]'s form: `user_id` of
  /// `sooplive://player/live?…`), lower case; null for anything else.
  static String? appLinkRoomId(String link) {
    final uri = Uri.tryParse(link.trim());
    if (uri == null || !uri.isScheme(_appScheme) || uri.host.toLowerCase() != 'player') return null;
    if (uri.pathSegments.firstOrNull?.toLowerCase() != 'live') return null;
    final id = uri.queryParameters['user_id']?.trim().toLowerCase() ?? '';
    return RegExp(r'^[a-z0-9_-]+$').hasMatch(id) ? id : null;
  }

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
  /// [areaName] (the area of every card, as in 3.x). Cards carry their
  /// start time and restriction, like every list (see [restrictionOf]).
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
  /// `TOTAL_CNT` non-zero on empty pages (REG-SOOP-007). The area is
  /// `broad_cate_name` (7-3); 3.x read `standard_broad_cate_name`, which
  /// the answers no longer carry, and is still read when that is missing.
  static List<LiveRoom> searchRooms(String body, {int status = 200}) {
    final root = _root(body, status: status, what: 'liveSearch');
    final result = root['RESULT'];
    if (result != null && jsonInt(result) != 1) {
      throw ApiChanged(_site, 'liveSearch: RESULT $result (${_snippet(body)})');
    }
    return [
      for (final raw in _listField(root['REAL_BROAD'], body, 'liveSearch'))
        if (_object(raw) case final item?)
          ?_card(
            item,
            cover: item['broad_img'],
            area: _display(jsonString(item['broad_cate_name']) ?? item['standard_broad_cate_name']),
          ),
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
  /// answers are the same), -2 blocked, and for a broadcast this client may
  /// not open: -6 age-restricted (login required), -8 age-restricted with a
  /// password, -14 subscribers only (S05-live-adult, -adult-password,
  /// -subscribers).
  static ({int result, Map<String, dynamic> channel}) channel(String body, {int status = 200}) {
    final root = _root(body, status: status, what: 'player_live_api');
    final channel = _object(root['CHANNEL']);
    if (channel == null) throw ApiChanged(_site, 'player_live_api: no CHANNEL (${_snippet(body)})');
    final result = jsonInt(channel['RESULT']);
    if (result == null) throw ApiChanged(_site, 'player_live_api: no CHANNEL.RESULT (${_snippet(body)})');
    return (result: result, channel: channel);
  }

  /// `player_live_api.php` `type=live`: the room as the user asked for it
  /// ([requestedId]; a follow keeps its identity), the same at every depth.
  ///
  /// - `RESULT` 1: live when `VIEWPRESET` is present, else offline (3.x's
  ///   rule); a live broadcast goes into [SoopRoomData], and with
  ///   [withDanmaku] the danmaku arguments carry [cookie]. Its restriction
  ///   comes from `BPWD`, `P_MIN_TIER` and `GRADE` ([LiveRestriction.none]
  ///   when none applies).
  /// - 0: offline (an unknown streamer too, which only room entry tells
  ///   apart, with the station); -2: banned. 3.x's room entry reported both
  ///   as a failed load; they show as they are now (7-4).
  /// - -6, -8, -14: live and restricted (adult, password, subscribers only;
  ///   7-5, 7-8): the answer names the title and the elapsed time (not for
  ///   -14) but no stream. 3.x showed an unknown state or failed.
  /// - anything else `ApiChanged`.
  ///
  /// Titles and names have their HTML entities decoded (7-2). The cover is
  /// the live thumbnail with 3.x's cache buster [now]; `BTIME` (seconds on
  /// air) before [now] is the start time. The answer has no audience
  /// figure, so the audience is empty (the station adds it at room entry).
  static LiveRoom roomDetail(
    String body, {
    required String requestedId,
    required DateTime now,
    String cookie = '',
    bool withDanmaku = false,
    int status = 200,
  }) {
    final answer = channel(body, status: status);
    final fields = answer.channel;
    final id = requestedId.trim();
    switch (answer.result) {
      case 1:
        break;
      case 0:
        return LiveRoom(roomId: id, platform: _site, liveStatus: LiveStatus.offline, link: roomPageUrl(id));
      case -2:
        return LiveRoom(roomId: id, platform: _site, liveStatus: LiveStatus.banned, link: roomPageUrl(id));
      case -6 || -8 || -14:
        return LiveRoom(
          roomId: id,
          platform: _site,
          title: _display(fields['TITLE']),
          liveStatus: LiveStatus.live,
          startedAt: startedBefore(fields['BTIME'], now),
          restriction: switch (answer.result) {
            -6 => LiveRestriction.adult,
            -8 => LiveRestriction.password,
            _ => LiveRestriction.subscribersOnly,
          },
          link: roomPageUrl(id),
        );
      default:
        throw ApiChanged(_site, 'player_live_api: RESULT ${answer.result}');
    }
    final bno = jsonString(fields['BNO']) ?? '';
    final bj = jsonString(fields['BJID']) ?? id;
    final tags = fields['CATEGORY_TAGS'];
    final live = fields['VIEWPRESET'] != null;
    final viewers = onlineViewers(fields);
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: _display(fields['TITLE']),
      nick: _display(fields['BJNICK']),
      avatar: bj.length < 2 ? '' : 'https://stimg.sooplive.co.kr/LOGO/${bj.substring(0, 2)}/$bj/$bj.jpg',
      cover: _cover(bno, now),
      area: tags is List && tags.isNotEmpty ? _text(tags.first) : '',
      watching: viewers,
      onlineViewers: viewers,
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: live ? LiveStatus.live : LiveStatus.offline,
      startedAt: live ? startedBefore(fields['BTIME'], now) : null,
      restriction: live
          ? restrictionOf(password: fields['BPWD'], subscribers: fields['P_MIN_TIER'], grade: fields['GRADE'])
          : null,
      link: roomPageUrl(id),
      introduction: '',
      notice: '',
      data: live
          ? SoopRoomData(
              bno: bno,
              rmd: _text(fields['RMD']).trim(),
              cdn: _text(fields['CDN']).trim(),
              presets: presets(fields['VIEWPRESET']),
              password: _truthy(fields['BPWD']),
            )
          : null,
      danmakuData: withDanmaku ? danmakuArgs(fields, roomId: id, cookie: cookie) : null,
    );
  }

  /// `chapi.sooplive.co.kr/api/<id>/station` (7-5). An unknown streamer
  /// is `NotFound` (HTTP 515, `code` 9000, S05-station-missing); other
  /// failures as every answer's.
  static SoopStation station(String body, {int status = 200}) {
    if (_decode(body) case {'code': final Object code} when jsonInt(code) == 9000) {
      throw NotFound(_site, 'station: no such streamer (${_snippet(body)})');
    }
    final root = _root(body, status: status, what: 'station');
    final station = _object(root['station']);
    if (station == null) throw ApiChanged(_site, 'station: no station object (${_snippet(body)})');
    final broad = _object(root['broad']);
    return SoopStation(
      nick: _display(station['user_nick']).trim(),
      avatar: normalizeImageUrl(root['profile_image']),
      introduction: _display(station['station_title']).trim(),
      broadcast: broad == null
          ? null
          : SoopStationBroadcast(
              bno: jsonString(broad['broad_no']) ?? '',
              title: _display(broad['broad_title']),
              viewers: switch (jsonCount(broad['current_sum_viewer'])) {
                final int count => '$count',
                null => '',
              },
              startedAt: koreanTime(station['broad_start']),
              restriction:
                  restrictionOf(
                    password: broad['is_password'],
                    subscribers: broad['subscription_only'],
                    grade: broad['broad_grade'],
                  ) ??
                  LiveRestriction.none,
            ),
    );
  }

  /// Room entry: [room] (the player API's answer) completed with the
  /// streamer's [station] (7-5). The station's profile picture, name when
  /// the answer has none, and tagline as the introduction; while live, its
  /// broadcast's viewers, and title, cover, start time and restriction
  /// where the answer lacks them (a restricted answer has no profile).
  ///
  /// A room the player API calls offline while the station names a
  /// broadcast is live: the platform shows it on air but gives this client
  /// no stream, so its restriction is the broadcast's, else
  /// [LiveRestriction.unplayable]. [now] is the cover's cache buster.
  static LiveRoom withStation(LiveRoom room, SoopStation station, {required DateTime now}) {
    final broadcast = station.broadcast;
    final profile = room.copyWith(
      nick: room.hasNick ? null : station.nick,
      avatar: station.avatar.isEmpty ? null : station.avatar,
      introduction: station.introduction.isEmpty ? null : station.introduction,
    );
    if (broadcast == null || profile.effectiveLiveStatus == LiveStatus.banned) return profile;
    final live = profile.isLiveNow;
    // A broadcast that ended between the two answers is not this one.
    if (profile.data case SoopRoomData(:final bno) when live && bno.isNotEmpty && bno != broadcast.bno) {
      return profile;
    }
    if (!live && profile.effectiveLiveStatus != LiveStatus.offline) return profile;
    return profile.copyWith(
      liveStatus: LiveStatus.live,
      title: profile.title.trim().isEmpty ? broadcast.title : null,
      cover: profile.cover.isEmpty ? _cover(broadcast.bno, now) : null,
      watching: broadcast.viewers.isEmpty ? null : broadcast.viewers,
      onlineViewers: broadcast.viewers.isEmpty ? null : broadcast.viewers,
      audienceMetricType: AudienceMetricType.onlineViewers,
      startedAt: profile.startedAt ?? broadcast.startedAt,
      restriction: live
          ? stricter(profile.restriction, broadcast.restriction)
          : (broadcast.restriction == LiveRestriction.none ? LiveRestriction.unplayable : broadcast.restriction),
    );
  }

  /// Why [room] (the player API's answer when a stream was asked for) has
  /// no stream: an age-restricted broadcast needs a login (`NeedsLogin`);
  /// a password, subscribers-only or otherwise unplayable one, or a room
  /// off the air, is `StreamUnavailable` naming the reason.
  static SiteError noStream(LiveRoom room) => switch (room.restriction) {
    LiveRestriction.adult => NeedsLogin(_site, 'player_live_api: ${room.roomId} is age-restricted'),
    LiveRestriction.password => StreamUnavailable(_site, 'player_live_api: ${room.roomId} is password-protected'),
    LiveRestriction.subscribersOnly => StreamUnavailable(
      _site,
      'player_live_api: ${room.roomId} is for subscribers only',
    ),
    _ => StreamUnavailable(_site, 'player_live_api: ${room.roomId} is ${room.effectiveLiveStatus.name}'),
  };

  /// The restriction a broadcast's flags state, or null when none of them
  /// is given: a password (`BPWD`, `is_password`: `Y`, `1`, `true`) before
  /// subscribers only (`P_MIN_TIER`, `subscription_only` above 0) before
  /// adult (grade 19); [LiveRestriction.none] when the flags say none. The
  /// order puts first what a login alone does not lift.
  static LiveRestriction? restrictionOf({Object? password, Object? subscribers, Object? grade}) {
    if (password == null && subscribers == null && grade == null) return null;
    if (_truthy(password)) return LiveRestriction.password;
    if ((jsonInt(subscribers) ?? 0) > 0) return LiveRestriction.subscribersOnly;
    if (jsonInt(grade) == 19) return LiveRestriction.adult;
    return LiveRestriction.none;
  }

  /// The stronger of two restrictions in [restrictionOf]'s order; null
  /// only when both are.
  static LiveRestriction? stricter(LiveRestriction? a, LiveRestriction? b) {
    const order = [
      LiveRestriction.password,
      LiveRestriction.subscribersOnly,
      LiveRestriction.adult,
      LiveRestriction.unplayable,
    ];
    for (final kind in order) {
      if (a == kind || b == kind) return kind;
    }
    return a ?? b;
  }

  /// A `broad_start` (`2026-09-22 19:59:31`, lists add `.0`) in UTC: SOOP
  /// writes Korean time (UTC+9; `BTIME` of the same broadcast and every
  /// list's latest start before its recording agree). Null when missing,
  /// malformed or not after 1970.
  static DateTime? koreanTime(Object? value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})(?:\.\d+)?$')
        .firstMatch(jsonString(value) ?? '');
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    final local = DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    if (local.month != parts[1] || local.day != parts[2] || local.hour != parts[3]) return null;
    final utc = local.subtract(_kst);
    return utc.millisecondsSinceEpoch > 0 ? utc : null;
  }

  /// The start of a broadcast on air for `BTIME` [seconds] at [now], to the
  /// second; null for a missing, zero or negative time.
  static DateTime? startedBefore(Object? seconds, DateTime now) {
    final elapsed = jsonInt(seconds);
    if (elapsed == null || elapsed <= 0) return null;
    final start = now.toUtc().millisecondsSinceEpoch ~/ 1000 - elapsed;
    return start > 0 ? DateTime.fromMillisecondsSinceEpoch(start * 1000, isUtc: true) : null;
  }

  /// The live thumbnail of broadcast [bno] with 3.x's cache buster.
  static String _cover(String bno, DateTime now) =>
      bno.isEmpty ? '' : 'https://liveimg.sooplive.co.kr/m/$bno?_t=${now.millisecondsSinceEpoch}';

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
  /// `chat-<CHIP as hex>.sooplive.com` (7-6), and the TLS port is
  /// `CHPT + 1`. Null without `CHATNO`, a host or a plain port below 65535
  /// (3.x connected nothing then).
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

  /// `chat-<IPv4 as eight hex digits>.sooplive.com`, or null: the domain of
  /// every chat host the API names (`CHDOMAIN`, e.g. `chat-6E0A4C4E` for
  /// `CHIP` 110.10.76.78 in S05-live-live), as the archived v4 built it
  /// (7-6; 3.x wrote `.sooplive.co.kr`).
  static String? _chatHost(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null || part < 0 || part > 255)) return null;
    return 'chat-${parts.map((part) => part!.toRadixString(16).padLeft(2, '0')).join().toUpperCase()}.sooplive.com';
  }

  // Streams -------------------------------------------------------------------

  /// Qualities of [presets] (3.x's `getPlayQualites`): `auto` and nameless
  /// entries left out, one per name (case ignored, the first wins), the
  /// request name as id, named by [qualityName], best first by
  /// [qualitySort].
  static List<LivePlayQuality> qualities(List<SoopPreset> presets) {
    final seen = <String>{};
    final options = <LivePlayQuality>[];
    for (final preset in presets) {
      final key = preset.name.toLowerCase();
      if (key == 'auto' || !seen.add(key)) continue;
      options.add(
        LivePlayQuality(
          quality: qualityName(preset),
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

  /// The name of [preset] (3.x's `LiveQualityLabel` names: 原画, 高清, 标清,
  /// …). The transcodes 3.x showed under their request names are named on
  /// the same scale (7-1): `hd4k` (720p) “超清”, and `hd8k` (the 1080p
  /// transcode of a 1440p source, S05-live-1440p) “蓝光”. Ids stay the
  /// request names, so no stored choice needs migrating.
  static String qualityName(SoopPreset preset) => switch (_token(preset.name)) {
    'hd8k' => '蓝光',
    'hd4k' => '超清',
    _ => LiveQualityLabel.normalize(
      platform: _site,
      rawLabel: preset.name,
      id: preset.name,
      bitrate: preset.bps > 0 ? preset.bps : null,
    ),
  };

  /// The order of a preset (3.x's `_qualitySort`): the name's tier first,
  /// the bitrate within it, so a source without a bitrate never falls
  /// below a transcode (REG-SOOP-004). Tiers: `original` > `master` >
  /// `fullhd`, `hd8k` (1080p) > `hd4k` (720p) > `hd` (540p) > `sd` > `low`;
  /// other names rank by bitrate alone, below every tier. `hd8k` and
  /// `hd4k`, which 3.x left without a tier and so listed after 360p, sit
  /// after the source by resolution (7-1). The other tiers' values are
  /// 3.x's.
  static int qualitySort(String name, int bps) {
    final tier = switch (_token(name)) {
      'original' || 'origin' || 'source' => 600000000,
      'master' || 'uhd' => 500000000,
      'fullhd' || 'fhd' || 'hd8k' => 400000000,
      'hd4k' => 350000000,
      'hd' => 300000000,
      'sd' || 'normal' => 200000000,
      'low' || 'ld' => 100000000,
      _ => 0,
    };
    return tier == 0 ? bps : tier + bps.clamp(0, 49999999);
  }

  static String _token(String name) => name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '');

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
  /// (3.x got an empty key and no URL), noting a [password] broadcast
  /// (asked without its password the key is refused with `RESULT` 0,
  /// S06-aid-password).
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
  ///
  /// Title and name have their entities decoded (7-2); `broad_start` is
  /// the start time (7-9); `is_password`, `subscription_only` and the grade
  /// (`broad_grade`, or `grade` in area lists) the restriction, the card
  /// staying live (restricted broadcasts are listed as 3.x listed them).
  static LiveRoom? _card(Map<String, dynamic> item, {required Object? cover, String avatar = '', String? area}) {
    final id = jsonString(item['user_id']);
    if (id == null) return null;
    final viewers = onlineViewers(item);
    return LiveRoom(
      roomId: id,
      platform: _site,
      title: _display(item['broad_title']),
      nick: _display(item['user_nick']),
      avatar: avatar.isEmpty ? SoopApi.avatar(id) : avatar,
      cover: normalizeImageUrl(cover),
      area: area,
      watching: viewers,
      onlineViewers: viewers,
      audienceMetricType: AudienceMetricType.onlineViewers,
      liveStatus: LiveStatus.live,
      startedAt: koreanTime(item['broad_start']),
      restriction: restrictionOf(
        password: item['is_password'],
        subscribers: item['subscription_only'],
        grade: item['broad_grade'] ?? item['grade'],
      ),
    );
  }
}

/// A field as 3.x wrote it (`toString()`), empty when missing (3.x wrote
/// "null" or threw).
String _text(Object? value) => value == null ? '' : '$value';

/// A title or name as shown: [_text] with HTML entities decoded (7-2).
String _display(Object? value) => decodeHtmlEntities(_text(value));

/// `true`, 1, and `true`, `Y`, `yes` or `1` in any case (`is_more`, `BPWD`,
/// `is_password`).
bool _truthy(Object? value) => switch (value) {
  true => true,
  final num number => number == 1,
  final String text => const {'true', 'y', 'yes', '1'}.contains(text.trim().toLowerCase()),
  _ => false,
};

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
  final decoded = _decode(body);
  if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not a JSON object (${_snippet(body)})');
  return decoded;
}

/// [body] as JSON, or null when it is not JSON.
Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
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
