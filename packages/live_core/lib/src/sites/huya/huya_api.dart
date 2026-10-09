import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_gift.dart';
import 'package:live_core/src/live_message.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/quality_label.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/tars.dart';
import 'package:meta/meta.dart';

const _site = 'huya';
const _web = 'https://www.huya.com';

/// Why an AntiCode could not be signed.
enum HuyaSignFailure {
  /// No hexadecimal `wsTime`, an `fm` that does not decode, or a template
  /// without all of `$0`–`$3` (3.x threw FormatException).
  malformed,

  /// The signing time is past `wsTime + 300 s`; the credential must be
  /// fetched again, never extended locally (3.x threw StateError).
  expired,
}

/// An AntiCode that cannot be signed. The reason never carries token
/// material.
@immutable
final class HuyaSignException implements Exception {
  /// Creates the failure.
  const new(this.kind, this.reason);

  /// What went wrong.
  final HuyaSignFailure kind;

  /// Diagnostic reason without secrets.
  final String reason;

  @override
  String toString() => 'HuyaSignException(${kind.name}: $reason)';
}

/// The milliseconds a signature uses for `seqid`: never behind the wall
/// clock and strictly increasing, so a player and a recorder opening the
/// same line in the same millisecond still get different `seqid` and
/// `wsSecret` (3.x `_lastSignatureMillis`).
final class HuyaSignClock {
  int _last = 0;

  /// The next signing millisecond at the wall time [now].
  int next(DateTime now) {
    final wall = now.millisecondsSinceEpoch;
    return _last = wall > _last ? wall : _last + 1;
  }
}

/// When a WUP `getCdnTokenInfoEx` token must be renewed and when it stops
/// opening connections.
typedef HuyaTokenWindow = ({DateTime refreshAt, DateTime invalidAt});

/// What the danmaku connection needs to join one room (3.x
/// `HuyaDanmakuArgs`): the streamer uid whose `live:`/`chat:` groups are
/// registered, and the channel ids. [topSid] is the headline message
/// board's `lPid`; [superChats] reads that board.
@immutable
final class HuyaDanmakuArgs {
  /// Creates the arguments.
  const new({required this.uid, required this.topSid, required this.subSid, this.superChats});

  /// Streamer uid (`profileInfo.uid`).
  final int uid;

  /// Top channel id; 0 when the room has none.
  final int topSid;

  /// Sub channel id; 0 when the room has none.
  final int subSid;

  /// Reads the headline message board (super chats); null when [topSid]
  /// is 0, as 3.x skipped the board then.
  final Future<List<LiveSuperChatMessage>> Function()? superChats;

  /// The JSON 3.x printed for these arguments.
  @override
  String toString() => jsonEncode({'uid': uid, 'topSid': topSid, 'subSid': subSid});
}

/// One CDN line of a live room before signing: a `multiLine` entry of the
/// FLV or HLS group joined with its `baseSteamInfoList` stream.
@immutable
final class HuyaLine {
  /// Creates a line.
  const new({
    required this.cdnType,
    required this.format,
    required this.base,
    required this.streamName,
    required this.antiCode,
    required this.presenterUid,
  });

  /// Server CDN code (`AL`, `TX`, `HS24`): `multiLine[].cdnType`.
  final String cdnType;

  /// FLV or HLS.
  final StreamFormat format;

  /// CDN base without the stream name; `http://` on huya.com hosts already
  /// upgraded to https.
  final String base;

  /// Stream name; also the key of the native WUP token request.
  final String streamName;

  /// The room's AntiCode for this format: `sFlvAntiCode` for FLV,
  /// `sHlsAntiCode` for HLS, never the other one.
  final String antiCode;

  /// The uid that signs a native FLV token: `lPresenterUid`, else
  /// `profileInfo.uid`, else `lChannelId`; 0 when none.
  final int presenterUid;

  /// Diagnostics without tokens or stream names.
  @override
  String toString() => 'HuyaLine($cdnType ${format.name} ${Uri.tryParse(base)?.host ?? 'unknown'})';
}

/// The `HuyaUserId` Tars structure, the `tId` of WUP calls (3.x
/// `core/tars/types.dart`).
@immutable
final class HuyaUserId {
  /// Creates an identity; every field defaults to empty or 0.
  const new({
    this.uid = 0,
    this.guid = '',
    this.token = '',
    this.huyaUa = '',
    this.cookie = '',
    this.tokenType = 0,
    this.deviceInfo = '',
    this.qimei = '',
  });

  /// Tag 0 `lUid`.
  final int uid;

  /// Tag 1 `sGuid`.
  final String guid;

  /// Tag 2 `sToken`.
  final String token;

  /// Tag 3 `sHuYaUA`.
  final String huyaUa;

  /// Tag 4 `sCookie`.
  final String cookie;

  /// Tag 5 `iTokenType`.
  final int tokenType;

  /// Tag 6 `sDeviceInfo`.
  final String deviceInfo;

  /// Tag 7 `sQIMEI`.
  final String qimei;

  /// Writes the fields in tag order.
  void writeTo(TarsWriter writer) => writer
    ..writeInt(0, uid)
    ..writeString(1, guid)
    ..writeString(2, token)
    ..writeString(3, huyaUa)
    ..writeString(4, cookie)
    ..writeInt(5, tokenType)
    ..writeString(6, deviceInfo)
    ..writeString(7, qimei);

  /// Diagnostics without the cookie or GUID.
  @override
  String toString() => 'HuyaUserId($huyaUa)';
}

/// The recording a replay room plays (`liveData.hls`, upgrade 3-1): a VOD
/// playlist that needs no signature and does not expire, and the video id
/// whose other definitions `moment/getMomentContent` lists.
@immutable
final class HuyaReplay {
  /// Creates the recording.
  const new({required this.url, this.videoId});

  /// The https playlist `profileRoom` names (the 360P definition when
  /// recorded).
  final String url;

  /// The recording's `vid`; null when the playlist does not carry one.
  final int? videoId;

  /// Diagnostics without the playlist's `srckey`.
  @override
  String toString() => 'HuyaReplay(${videoId ?? Uri.tryParse(url)?.host ?? 'unknown'})';
}

/// A `profileRoom` answer: the room as the user asked for it, the ids
/// streams and danmaku need, and, for a live room, its qualities and (with
/// a `stream`) its lines. A replay with a recording has `replay` and that
/// recording's one quality.
typedef HuyaProfile = ({
  LiveRoom room,
  int presenterUid,
  int topSid,
  int subSid,
  bool hasStream,
  List<HuyaLine> lines,
  List<LivePlayQuality> qualities,
  HuyaReplay? replay,
});

/// Pure parsing, signing and Tars payloads of Huya (3.x's `HuyaSite`,
/// `huya_utils.dart`, `huya_transport_policy.dart` and `core/tars`, with the
/// archived v4 parser's fixes). Each response function takes the response
/// body and status and returns 3.x's models or throws a `SiteError`.
abstract final class HuyaApi {
  /// Mobile Chrome, the UA of 3.x's API requests (`kUserAgent`).
  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/90.0.4430.91 Mobile Safari/537.36 Edg/117.0.0.0';

  /// Huya's PC client UA: the media requests' default, the native WUP token
  /// request and the message board (3.x `HuyaRequestParams.hysdkUa`), at
  /// the client version upstream and simple_live send (upstream a858550bb).
  static const String hysdkUserAgent = 'HYSDK(Windows,30000002)_APP(pc_exe&7100004&official)_SDK(trans&2.40.0.6448)';

  /// A desktop Chrome UA for room pages (alias lookup).
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/140.0.0.0 Safari/537.36';

  /// `tId.sHuYaUA` of the native token request.
  static const String nativeTarsUserAgent = 'pc_exe&7060000&official';

  /// `tId.sHuYaUA` of the web token request (the web player's
  /// `TafLink.getUserId()`).
  static const String webTarsUserAgent = 'webh5&0.1.0&websocket';

  /// `iAppId` of token requests; never the page's `vappid=10057`.
  static const int tokenAppId = 66;

  /// The four fixed top-level categories, in platform order.
  static const List<({String id, String name})> topCategories = [
    (id: '1', name: '网游'),
    (id: '2', name: '单机'),
    (id: '8', name: '娱乐'),
    (id: '3', name: '手游'),
  ];

  /// Rank of the source quality (bit rate 0), above every transcode.
  static const int sourceRank = 1 << 30;

  /// The `definition` of a replay's source recording.
  static const String replaySourceDefinition = 'yuanhua';

  /// Names of the replay definitions seen in `getMomentContent` (S15-vod),
  /// for the one quality `profileRoom` names when that list is not read.
  static const Map<String, String> replayDefinitionNames = {
    replaySourceDefinition: '原画',
    '1300': '720P',
    '350': '360P',
  };

  // Catalog -------------------------------------------------------------------

  /// `bussLive?bussType=` → the areas of one top-level category in server
  /// order. `gid` may be written as `2165.0`; the area id is `"2165"`.
  static List<LiveArea> areas(
    String body, {
    required String categoryId,
    required String categoryName,
    int status = 200,
  }) {
    final root = _envelope(body, status: status, what: 'bussLive');
    return [
      for (final raw in _list(root['data']))
        if (_object(raw) case final item? when _positive(item['gid']) != null)
          LiveArea(
            platform: _site,
            areaId: '${_positive(item['gid'])}',
            areaName: _text(item['gameFullName']),
            areaType: categoryId,
            typeName: categoryName,
            areaPic: 'https://huyaimg.msstatic.com/cdnimage/game/${_positive(item['gid'])}-MS.jpg',
          ),
    ];
  }

  /// `getLiveListByPage` (recommendations without `gameId`, an area with
  /// it): every listed room is live; the audience is popularity. More
  /// pages follow until `totalPage` or an empty `datas` (past the last page
  /// `totalPage` reads 1). `isRoomPay` marks a paid room (M2.1); the list
  /// has no start time.
  static ({List<LiveRoom> rooms, bool hasMore}) roomList(String body, {required int page, int status = 200}) {
    final root = _envelope(body, status: status, what: 'getLiveListByPage');
    final data = _object(root['data']);
    final raw = data?['datas'];
    if (raw is! List) throw ApiChanged(_site, 'getLiveListByPage: no datas (${_snippet(body)})');
    final rooms = [
      for (final item in raw)
        if (_object(item) case final room? when _roomId(room['profileRoom']) != null)
          LiveRoom(
            roomId: _roomId(room['profileRoom']),
            platform: _site,
            title: _title(room['introduction'], room['roomName']),
            nick: _text(room['nick']),
            avatar: normalizeImageUrl(room['avatar180']),
            cover: _thumbnail(room['screenshot']),
            area: _text(room['gameFullName']),
            watching: _count(room['totalCount']),
            popularity: _count(room['totalCount']),
            audienceMetricType: AudienceMetricType.popularity,
            liveStatus: LiveStatus.live,
            restriction: switch (_flag(room['isRoomPay'])) {
              true => LiveRestriction.paid,
              false => LiveRestriction.none,
              null => null,
            },
          ),
    ];
    final totalPage = jsonInt(data?['totalPage']) ?? 0;
    return (rooms: rooms, hasMore: raw.isNotEmpty && (totalPage <= 0 || page < totalPage));
  }

  // Search --------------------------------------------------------------------

  /// `getSearchContent&v=4`: live rooms (`response.3`) for the request's
  /// [start] and [rows]. The room id is the streamer entry's
  /// (`response.1`) with the same `uid` and `yyid`, else the room entry's.
  ///
  /// A later page repeats every earlier result first (`start=20&rows=20`
  /// answers 40 docs): when there are more docs than [rows], the first
  /// [start] are skipped, and a room already seen in the response is not
  /// repeated. 3.x showed all of them. The docs tell neither the start time
  /// nor restrictions, so both stay unknown (null).
  static List<LiveRoom> searchRooms(String body, {required int start, required int rows, int status = 200}) {
    final response = _object(_json(body, status: status, what: 'getSearchContent')['response']);
    if (response == null) throw ApiChanged(_site, 'getSearchContent: no response (${_snippet(body)})');
    final docs = _list(_object(response['3'])?['docs']);
    final streamers = _list(_object(response['1'])?['docs']);

    String? roomIdOf(Map<String, dynamic> doc) {
      final uid = jsonString(doc['uid']);
      final yyid = jsonString(doc['yyid']);
      if (uid != null && yyid != null) {
        for (final raw in streamers) {
          final streamer = _object(raw);
          if (streamer != null && jsonString(streamer['uid']) == uid && jsonString(streamer['yyid']) == yyid) {
            if (_roomId(streamer['room_id']) case final id?) return id;
          }
        }
      }
      return _roomId(doc['room_id']);
    }

    final skipped = docs.length > rows ? min(max(start, 0), docs.length) : 0;
    final seen = <String>{};
    final rooms = <LiveRoom>[];
    for (final (index, raw) in docs.indexed) {
      final doc = _object(raw);
      final id = doc == null ? null : roomIdOf(doc);
      if (doc == null || id == null || !seen.add(id) || index < skipped) continue;
      rooms.add(
        LiveRoom(
          roomId: id,
          platform: _site,
          userId: jsonString(doc['yyid']) ?? '',
          title: _title(doc['game_introduction'], doc['game_roomName']),
          nick: _text(doc['game_nick']),
          avatar: normalizeImageUrl(doc['game_imgUrl']),
          cover: _thumbnail(doc['game_screenshot']),
          area: _text(doc['gameName']),
          watching: _count(doc['game_total_count']),
          popularity: _count(doc['game_total_count']),
          audienceMetricType: AudienceMetricType.popularity,
          liveStatus: LiveStatus.live,
        ),
      );
    }
    return rooms;
  }

  /// `getSearchContent&v=1`: streamers (`response.1`), live or not.
  static List<LiveAnchorItem> searchAnchors(String body, {int status = 200}) {
    final response = _object(_json(body, status: status, what: 'getSearchContent')['response']);
    if (response == null) throw ApiChanged(_site, 'getSearchContent: no response (${_snippet(body)})');
    return [
      for (final raw in _list(_object(response['1'])?['docs']))
        if (_object(raw) case final doc? when _roomId(doc['room_id']) != null)
          LiveAnchorItem(
            roomId: _roomId(doc['room_id'])!,
            avatar: normalizeImageUrl(doc['game_avatarUrl180']),
            userName: _text(doc['game_nick']),
            liveStatus: doc['gameLiveOn'] == true || jsonInt(doc['gameLiveOn']) == 1,
          ),
    ];
  }

  // Rooms ---------------------------------------------------------------------

  /// `profileRoom`: the room as the user asked for it ([requestedId]: the
  /// identity of a follow never changes).
  ///
  /// - `status` 422 (a missing room, or a letter alias) is `NotFound`; any
  ///   other non-200 status or a `data` that is not an object is
  ///   `ApiChanged`.
  /// - `liveStatus` `ON` is live; `REPLAY` is a replay, shown as 3.x did;
  ///   `OFF`, `OFFLINE` and `CLOSED` are offline; anything else is
  ///   `ApiChanged`, never offline.
  /// - A replay plays its recording (`liveData.hls`, else `hlsUrl`: an
  ///   `.m3u8` VOD 3.x never played, upgrade 3-1) with restriction `none`;
  ///   one without a recording is `unplayable` (grouped with offline rooms).
  /// - A live room's restriction as the web player reads it: `isRoomPay`
  ///   (the page's `isPayRoom`) is `paid`; else `liveData.isSecret` 1 is
  ///   `password` (a secret room); else `none`. Its `startedAt` is
  ///   `liveData.startTime` (Unix seconds). An offline room has neither.
  /// - Every count is popularity: `totalCount`, else `userCount`.
  /// - topSid / subSid: the first positive `lChannelId` / `lSubChannelId`
  ///   of `baseSteamInfoList`, else `chTopId` / `subChId`.
  /// - Qualities for a live room, or the recording's one quality; lines
  ///   only when a live room has a `stream`.
  static HuyaProfile profile(String body, {required String requestedId, int status = 200}) {
    final root = _json(body, status: status, what: 'profileRoom');
    final code = jsonInt(root['status']);
    final message = jsonString(root['message']) ?? '';
    if (code == 422) throw NotFound(_site, 'profileRoom 422 $message'.trim());
    if (code != 200) throw ApiChanged(_site, 'profileRoom status $code $message'.trim());
    final data = _object(root['data']);
    if (data == null) throw ApiChanged(_site, 'profileRoom: data is not an object (${_snippet(body)})');
    final state = switch (jsonString(data['liveStatus'])?.toUpperCase()) {
      'ON' => LiveStatus.live,
      'REPLAY' => LiveStatus.replay,
      'OFF' || 'OFFLINE' || 'CLOSED' => LiveStatus.offline,
      final other => throw ApiChanged(_site, 'profileRoom: liveStatus ${other ?? 'missing'}'),
    };
    final live = _object(data['liveData']) ?? const <String, dynamic>{};
    final info = _object(data['profileInfo']) ?? const <String, dynamic>{};
    final stream = _object(data['stream']);
    final bases = [for (final raw in _list(stream?['baseSteamInfoList'])) ?_object(raw)];
    int channel(String key, String fallback) =>
        bases.map((base) => _positive(base[key])).nonNulls.firstOrNull ?? _positive(data[fallback]) ?? 0;
    final presenterUid = jsonInt(info['uid']) ?? jsonInt(live['uid']) ?? 0;
    final popularity = _count(live['totalCount']).ifEmpty(() => _count(live['userCount']));
    final id = requestedId.trim();
    final isLive = state == LiveStatus.live;
    final hasStream = isLive && stream != null;
    final replay = state == LiveStatus.replay ? _replayOf(live) : null;
    final startTime = isLive ? _positive(live['startTime']) : null;
    return (
      room: LiveRoom(
        roomId: id,
        platform: _site,
        title: _title(live['introduction'], live['roomName']),
        nick: _text(info['nick']),
        avatar: normalizeImageUrl(info['avatar180']),
        cover: normalizeImageUrl(live['screenshot']),
        area: _text(live['gameFullName']),
        watching: popularity,
        popularity: popularity,
        audienceMetricType: AudienceMetricType.popularity,
        liveStatus: state,
        introduction: _text(live['introduction']),
        notice: _text(data['welcomeText']),
        link: '$_web/$id',
        startedAt: startTime == null ? null : DateTime.fromMillisecondsSinceEpoch(startTime * 1000, isUtc: true),
        restriction: switch (state) {
          LiveStatus.live => _liveRestriction(data, live),
          LiveStatus.replay => replay == null ? LiveRestriction.unplayable : LiveRestriction.none,
          _ => null,
        },
      ),
      presenterUid: presenterUid,
      topSid: channel('lChannelId', 'chTopId'),
      subSid: channel('lSubChannelId', 'subChId'),
      hasStream: hasStream,
      lines: hasStream ? _lines(stream, bases, jsonInt(info['uid'])) : const [],
      qualities: isLive
          ? qualities(data)
          : replay != null
          ? [replayQuality(replay.url)]
          : const [],
      replay: replay,
    );
  }

  /// A live room's restriction, read as the web player does: a paid room
  /// (`isRoomPay` of `data` or `liveData`, the page's `isPayRoom`) plays
  /// only for buyers; a secret room (`isSecret` 1 and not paid) asks for its
  /// password and the player does not open its stream. Null when the answer
  /// has none of the flags.
  static LiveRestriction? _liveRestriction(Map<String, dynamic> data, Map<String, dynamic> live) {
    final paid = [data['isRoomPay'], live['isRoomPay'], data['isPayRoom']].map(_flag).nonNulls;
    final secret = [live['isSecret'], data['isSecret']].map(_flag).nonNulls;
    if (paid.isEmpty && secret.isEmpty) return null;
    if (paid.contains(true)) return LiveRestriction.paid;
    return secret.contains(true) ? LiveRestriction.password : LiveRestriction.none;
  }

  /// The recording of a replay: `liveData.hls`, else `hlsUrl`, when it is
  /// an http(s) `.m3u8`; its `vid` names the video.
  static HuyaReplay? _replayOf(Map<String, dynamic> live) {
    for (final key in const ['hls', 'hlsUrl']) {
      final url = replayUrl(live[key]);
      if (url == null) continue;
      return HuyaReplay(url: url, videoId: _positive(_parseMap(Uri.parse(url).query)['vid']));
    }
    return null;
  }

  /// A recording playlist: an http(s) `.m3u8` URL, `http://` on huya.com
  /// upgraded to https (the VOD CDN serves both); null for anything else,
  /// so a live quality's bit rate is never taken for a recording.
  static String? replayUrl(Object? value) {
    if (value is! String) return null;
    final uri = jsonUrl(value);
    if (uri == null || !uri.path.toLowerCase().endsWith('.m3u8')) return null;
    return secureBase(value.trim());
  }

  /// The one quality of the recording at [url], named by its `definition`
  /// ([replayDefinitionNames]; `默认` when unknown). Its id is the
  /// definition, its data the URL.
  static LivePlayQuality replayQuality(String url) {
    final definition = jsonString(_parseMap(Uri.tryParse(url)?.query ?? '')['definition']);
    return LivePlayQuality(
      quality: replayDefinitionNames[definition] ?? '默认',
      id: definition,
      data: url,
      sort: definition == replaySourceDefinition ? sourceRank : 0,
    );
  }

  /// `moment/getMomentContent?videoId=`: every definition of a replay's
  /// recording (S15-vod: 1080P source, 720P, 360P, all H.264 HLS), the
  /// source first, then by height. The source (`definition=yuanhua` in its
  /// URL) is named `原画` (the unified quality naming); the others keep the
  /// platform's `defName`. Ids are the URL's `definition` (`yuanhua`,
  /// `1300`, `350`), the same as [replayQuality]'s; data is the https
  /// playlist. A missing video answers an empty list (S15-vod-missing).
  static List<LivePlayQuality> replayQualities(String body, {int status = 200}) {
    final root = _envelope(body, status: status, what: 'getMomentContent');
    final info = _object(_object(_object(root['data'])?['moment'])?['videoInfo']);
    final seen = <String>{};
    final qualities = <LivePlayQuality>[];
    for (final raw in _list(info?['definitions'])) {
      final item = _object(raw);
      final url = replayUrl(item?['m3u8']) ?? replayUrl(item?['url']);
      if (item == null || url == null) continue;
      final fallback = replayQuality(url);
      if (!seen.add('${fallback.selectionId}')) continue;
      final source = fallback.sort == sourceRank;
      final name = jsonString(item['defName']);
      qualities.add(
        LivePlayQuality(
          quality: source || name == null
              ? fallback.quality
              : LiveQualityLabel.normalize(platform: _site, rawLabel: name, id: fallback.id),
          id: fallback.id,
          data: url,
          sort: source ? sourceRank : max(jsonInt(item['height']) ?? 0, 0),
        ),
      );
    }
    return qualities..sort((a, b) => b.sort.compareTo(a.sort));
  }

  /// Lines: `stream.flv.multiLine` then `stream.hls.multiLine`, server order,
  /// entries with a non-empty `url` whose `cdnType` matches a base stream's
  /// `sCdnType`. Base streams that `multiLine` does not list are left out.
  static List<HuyaLine> _lines(Map<String, dynamic> stream, List<Map<String, dynamic>> bases, int? profileUid) {
    final lines = <HuyaLine>[];
    final seen = <String>{};
    for (final (format, key, urlKey, codeKey) in const [
      (StreamFormat.flv, 'flv', 'sFlvUrl', 'sFlvAntiCode'),
      (StreamFormat.hls, 'hls', 'sHlsUrl', 'sHlsAntiCode'),
    ]) {
      for (final raw in _list(_object(stream[key])?['multiLine'])) {
        final item = _object(raw);
        final cdn = jsonString(item?['cdnType']);
        if (item == null || cdn == null || jsonString(item['url']) == null) continue;
        final base = bases.where((base) => jsonString(base['sCdnType']) == cdn).firstOrNull;
        final url = jsonString(base?[urlKey]);
        final name = jsonString(base?['sStreamName']);
        if (base == null || url == null || name == null || !seen.add('${format.name}:$cdn')) continue;
        lines.add(
          HuyaLine(
            cdnType: cdn,
            format: format,
            base: secureBase(url),
            streamName: name,
            antiCode: jsonString(base[codeKey]) ?? '',
            presenterUid: jsonInt(base['lPresenterUid']) ?? profileUid ?? jsonInt(base['lChannelId']) ?? 0,
          ),
        );
      }
    }
    return lines;
  }

  /// Qualities of a live room's `data`: the rate list is
  /// `liveData.bitRateInfo` (a JSON string or a list), else
  /// `stream.flv.rateArray`. The id is the bit rate (0 is the source);
  /// blank names and negative rates are dropped, the first of a rate wins;
  /// the source first, then by rate. Without rates, one "原画" at 0: no
  /// invented transcode (REG-HUYA-013).
  static List<LivePlayQuality> qualities(Map<String, dynamic> data) {
    Object? info = _object(data['liveData'])?['bitRateInfo'];
    if (info is String) {
      try {
        info = info.trim().isEmpty ? null : jsonDecode(info);
      } on FormatException {
        info = null;
      }
    }
    final rates = info is List ? info : _list(_object(_object(_object(data['stream'])?['flv']))?['rateArray']);
    final seen = <int>{};
    final named = <({String name, int rate})>[];
    for (final raw in rates) {
      final item = _object(raw);
      final name = jsonString(item?['sDisplayName']);
      final rate = jsonInt(item?['iBitRate']);
      if (name == null || rate == null || rate < 0 || !seen.add(rate)) continue;
      named.add((name: name, rate: rate));
    }
    if (named.isEmpty) named.add((name: '原画', rate: 0));
    return [
      for (final (:name, :rate) in named)
        LivePlayQuality(
          quality: LiveQualityLabel.normalize(
            platform: _site,
            rawLabel: name,
            id: rate,
            bitrate: rate > 0 ? rate * 1000 : null,
          ),
          id: rate,
          data: rate,
          sort: rate == 0 ? sourceRank : rate,
        ),
    ]..sort((a, b) => b.sort.compareTo(a.sort));
  }

  // Streams -------------------------------------------------------------------

  /// An `http://` base on a huya.com host becomes https; other hosts stay.
  static String secureBase(String base) {
    final uri = Uri.tryParse(base);
    if (uri == null || uri.scheme != 'http' || !_isHuyaHost(uri.host)) return base;
    return uri.replace(scheme: 'https').toString();
  }

  static final RegExp _templateKey = RegExp('(^|&)fm=');

  /// Whether [antiCode] carries an `fm` key (3.x's test before signing;
  /// an empty `fm` then signs as the query unchanged).
  static bool hasTemplate(String antiCode) => _templateKey.hasMatch(antiCode);

  /// Signs [antiCode] for [streamName] as [uid] (3.x `buildAntiCode`). A
  /// query without an `fm` value is returned unchanged. Parameters the
  /// signer does not own keep their spelling and position.
  ///
  /// - `seqid = uid + clock.next(now)`; `hash = md5("seqid|ctype|t")`;
  ///   `ctype` defaults to `huya_webh5`, `t` to `100`; `t=103` is WAP.
  /// - `wsSecret = md5(template)` with the first `$0` replaced by the
  ///   rotated uid (the uid itself for WAP), `$1` by the stream, `$2` by
  ///   the hash and `$3` by `wsTime` (lower case). The whole server template
  ///   is used; no layout is assumed (REG-HUYA-005).
  /// - Output: `wsSecret seqid u uid uuid fm` removed, then `wsSecret`,
  ///   `wsTime`, `seqid`, `ctype`, `ver=1`, `fs` (default `bgct`), `t`, and
  ///   `u` (WAP: `uid` and a random `uuid`), an existing key replaced in
  ///   place, a missing one appended.
  ///
  /// Throws [HuyaSignException]: `malformed` without a hexadecimal
  /// `wsTime`, with an `fm` that does not decode or a template missing a
  /// placeholder; `expired` past `wsTime + 300 s` (never extended,
  /// REG-HUYA-004).
  static String signAntiCode(
    String antiCode, {
    required String streamName,
    required int uid,
    required HuyaSignClock clock,
    required DateTime now,
    Random? random,
  }) {
    final params = _parse(antiCode);
    String? value(String key) {
      for (final param in params) {
        if (param.key != key) continue;
        try {
          if (RegExp('%(?![0-9A-Fa-f]{2})').hasMatch(param.value)) throw const FormatException();
          return Uri.decodeComponent(param.value).trim();
        } on FormatException {
          throw HuyaSignException(HuyaSignFailure.malformed, '$key is not percent-encoded UTF-8');
        }
      }
      return null;
    }

    String orDefault(String? value, String fallback) => value == null || value.isEmpty ? fallback : value;

    final fm = value('fm') ?? '';
    if (fm.isEmpty) return antiCode;
    if (uid <= 0) throw const HuyaSignException(HuyaSignFailure.malformed, 'no signing uid');
    final ctype = orDefault(value('ctype'), 'huya_webh5');
    final platform = orDefault(value('t'), '100');
    final wap = platform == '103';
    final wsTime = (value('wsTime') ?? '').toLowerCase();
    final wsSeconds = RegExp(r'^[0-9a-f]+$').hasMatch(wsTime) ? int.tryParse(wsTime, radix: 16) : null;
    if (wsSeconds == null) throw const HuyaSignException(HuyaSignFailure.malformed, 'no hexadecimal wsTime');
    final String template;
    try {
      template = utf8.decode(base64.decode(base64.normalize(fm)));
    } on FormatException {
      throw const HuyaSignException(HuyaSignFailure.malformed, 'fm is not base64 UTF-8');
    }
    if (!const [r'$0', r'$1', r'$2', r'$3'].every(template.contains)) {
      throw const HuyaSignException(HuyaSignFailure.malformed, r'fm template lacks $0-$3');
    }

    final millis = clock.next(now);
    if (millis ~/ 1000 > wsSeconds + 300) {
      throw const HuyaSignException(HuyaSignFailure.expired, 'wsTime + 300 s has passed');
    }
    final seqId = uid + millis;
    final hash = md5.convert(utf8.encode('$seqId|$ctype|$platform')).toString();
    final rotated = rotateUid(uid);
    final secret = template
        .replaceFirst(r'$0', '${wap ? uid : rotated}')
        .replaceFirst(r'$1', streamName)
        .replaceFirst(r'$2', hash)
        .replaceFirst(r'$3', wsTime);
    final wsSecret = md5.convert(utf8.encode(secret)).toString();

    final output = [
      for (final param in params)
        if (!const {'wsSecret', 'seqid', 'u', 'uid', 'uuid', 'fm'}.contains(param.key))
          (key: param.key, raw: param.raw),
    ];
    void put(String key, String value) {
      final segment = (key: key, raw: '$key=${Uri.encodeQueryComponent(value)}');
      final index = output.indexWhere((param) => param.key == key);
      if (index < 0) {
        output.add(segment);
      } else {
        output[index] = segment;
      }
    }

    put('wsSecret', wsSecret);
    put('wsTime', wsTime);
    put('seqid', '$seqId');
    put('ctype', ctype);
    put('ver', '1');
    put('fs', value('fs') ?? 'bgct');
    put('t', platform);
    if (wap) {
      final rng = random ?? Random();
      final ct = ((wsSeconds + rng.nextDouble()) * 1000).toInt();
      final uuid = (((ct % 1e10) + rng.nextDouble()) * 1e3 % 0xffffffff).toInt();
      put('uid', '$uid');
      put('uuid', '$uuid');
    } else {
      put('u', '$rotated');
    }
    return output.map((param) => param.raw).join('&');
  }

  /// `u = rotl64(uid)`: the low 32 bits rotate left by 8, the high 32 bits
  /// stay (REG-HUYA-008: anonymous uids are above 2^32).
  static int rotateUid(int uid) {
    final low = uid & 0xFFFFFFFF;
    return (uid - low) | (((low << 8) | (low >> 24)) & 0xFFFFFFFF);
  }

  /// The inverse of [rotateUid].
  static int unrotateUid(int value) {
    final low = value & 0xFFFFFFFF;
    return (value - low) | (((low >> 8) | (low << 24)) & 0xFFFFFFFF);
  }

  /// The media query for [bitRate] (3.x `getPlayUrl`): `codec=264` added
  /// when absent (`codec=265` with [hevc]); `ratio` set to the rate, or
  /// removed for the source (0), never the one captured with the page
  /// (REG-HUYA-012).
  ///
  /// `codec=265` is what the web player adds when it can decode HEVC; a room
  /// without an HEVC transcode still answers H.264 (2026-10-01: two of three
  /// rooms sent HEVC, the third H.264).
  static String mediaQuery(String antiCode, {required int bitRate, bool hevc = false}) {
    final query = RegExp('(^|&)codec=').hasMatch(antiCode) ? antiCode : '$antiCode&codec=${hevc ? 265 : 264}';
    return replaceQueryParameter(query, 'ratio', bitRate > 0 ? '$bitRate' : null);
  }

  /// [query] with the first [key] set to [value] in place and later ones
  /// removed; appended when absent; removed entirely when [value] is null.
  /// Empty segments are dropped.
  static String replaceQueryParameter(String query, String key, String? value) {
    final output = <String>[];
    var replaced = false;
    for (final segment in query.split('&')) {
      if (segment.isEmpty) continue;
      final separator = segment.indexOf('=');
      if ((separator < 0 ? segment : segment.substring(0, separator)) != key) {
        output.add(segment);
        continue;
      }
      if (!replaced && value != null) output.add('$key=$value');
      replaced = true;
    }
    if (!replaced && value != null) output.add('$key=$value');
    return output.join('&');
  }

  /// `{base}/{streamName}.{flv|m3u8}?{mediaQuery}`. [hevc] asks an FLV line
  /// for HEVC; HLS always asks for H.264 (the web player's HEVC HLS is a
  /// separate URL).
  static Uri mediaUrl(HuyaLine line, {required String antiCode, required int bitRate, bool hevc = false}) {
    final base = line.base.endsWith('/') ? line.base.substring(0, line.base.length - 1) : line.base;
    final extension = line.format == StreamFormat.hls ? 'm3u8' : 'flv';
    final query = mediaQuery(antiCode, bitRate: bitRate, hevc: hevc && line.format == StreamFormat.flv);
    return Uri.parse('$base/${line.streamName}.$extension?$query');
  }

  /// The video codec a media URL is known to deliver: `codec=264` is AVC.
  /// `codec=265` only asks for HEVC (a room without an HEVC transcode
  /// answers H.264), so it is unknown (null).
  static String? codecOf(Uri url) => switch (_parseMap(url.query)['codec']) {
    '264' => 'avc',
    _ => null,
  };

  /// Media request headers for [roomId], the same for playing and recording
  /// (3.x `PlaybackHeaderResolver`): [userAgent] (the HYSDK UA unless the
  /// player configuration named another), Origin, the room page as Referer,
  /// and the login cookie when there is one.
  static Map<String, String> mediaHeaders(String roomId, {String userAgent = hysdkUserAgent, String? cookie}) {
    final id = Uri.encodeComponent(roomId.trim());
    return {
      'user-agent': userAgent,
      'origin': _web,
      'referer': id.isEmpty ? '$_web/' : '$_web/$id',
      if (cookie != null && cookie.trim().isNotEmpty) 'cookie': cookie.trim(),
    };
  }

  // Leases --------------------------------------------------------------------

  /// A native signed FLV: a huya.com `.flv` with `ctype=huya_pc_exe` and
  /// `t=100`. Its credential only limits new connections.
  static bool isNativeFlv(Uri url) {
    final query = _parseMap(url.query);
    return _isHuyaHost(url.host) &&
        url.path.toLowerCase().endsWith('.flv') &&
        query['ctype'] == 'huya_pc_exe' &&
        query['t'] == '100';
  }

  /// A web FLV (static tokens too) or HLS on huya.com: the CDN closes the
  /// connection about two minutes after the URL was issued.
  static bool hasShortTransportLease(Uri url) {
    final path = url.path.toLowerCase();
    return _isHuyaHost(url.host) && (path.endsWith('.flv') || path.endsWith('.m3u8')) && !isNativeFlv(url);
  }

  /// When a signed URL was issued: `seqid − uid`, the uid being `u` rotated
  /// back (WAP `t=103`: `uid`); null without a plausible value.
  static DateTime? signedIssuedAt(Uri url) {
    final query = _parseMap(url.query);
    final wap = query['t'] == '103';
    final seqId = int.tryParse(query['seqid'] ?? '');
    final encoded = int.tryParse(query[wap ? 'uid' : 'u'] ?? '');
    if (seqId == null || encoded == null) return null;
    final millis = seqId - (wap ? encoded : unrotateUid(encoded));
    if (millis < DateTime.utc(2020).millisecondsSinceEpoch || millis > DateTime.utc(2100).millisecondsSinceEpoch) {
      return null;
    }
    final issuedAt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    final signedInvalidAt = _wsTime(query['wsTime'])?.add(const Duration(minutes: 5));
    return signedInvalidAt != null && issuedAt.isAfter(signedInvalidAt) ? null : issuedAt;
  }

  /// The lease of a media [url] (3.x `getPlayUrlRefreshAt` and
  /// `getPlayUrlInvalidAt`):
  ///
  /// - invalid at the earliest of `wsTime + 300 s`, the WUP [token]'s end
  ///   and, for a short transport lease, issue + 125 s;
  /// - refreshed at the earliest of `wsTime + 270 s`, the token's refresh
  ///   time and issue + 100 s;
  /// - the issue time is [signedIssuedAt], else [builtAt] (a static token
  ///   without `seqid`, REG-HUYA-019);
  /// - expiry cuts the connection only for a short transport lease; a
  ///   native FLV is only prefetched (REG-HUYA-002).
  ///
  /// Null when nothing bounds the URL.
  static PlayLease? lease(Uri url, {DateTime? builtAt, HuyaTokenWindow? token}) {
    final signedInvalidAt = _wsTime(_parseMap(url.query)['wsTime'])?.add(const Duration(minutes: 5));
    final issuedAt = hasShortTransportLease(url) ? signedIssuedAt(url) ?? builtAt?.toUtc() : null;
    final invalidAt = _earliest([signedInvalidAt, token?.invalidAt, issuedAt?.add(const Duration(seconds: 125))]);
    if (invalidAt == null) return null;
    return PlayLease(
      refreshAt: _earliest([
        signedInvalidAt?.subtract(const Duration(seconds: 30)),
        token?.refreshAt,
        issuedAt?.add(const Duration(seconds: 100)),
      ])!,
      expiresAt: invalidAt,
      cutsConnection: issuedAt != null,
    );
  }

  /// The window of a WUP token received at [receivedAt] (3.x
  /// `HuyaCdnTokenLease.fromResponse`): valid until `wsTime + 300 s`, or the
  /// earlier bound `iExpireTime` gives (above 10^12 milliseconds, above
  /// 10^9 seconds, else seconds after receipt); refreshed 30 s before. An
  /// empty token or one without a hexadecimal `wsTime` is `ApiChanged`.
  static HuyaTokenWindow tokenWindow(String token, {required int expireTime, required DateTime receivedAt}) {
    if (token.trim().isEmpty) throw const ApiChanged(_site, 'getCdnTokenInfoEx: empty sFlvToken');
    final wsTime = _wsTime(_parseMap(token.trim())['wsTime']);
    if (wsTime == null) throw const ApiChanged(_site, 'getCdnTokenInfoEx: sFlvToken without wsTime');
    var invalidAt = wsTime.add(const Duration(minutes: 5));
    if (expireTime > 0) {
      final bound = expireTime > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(min(expireTime, 8640000000000000), isUtc: true)
          : expireTime > 1000000000
          ? DateTime.fromMillisecondsSinceEpoch(expireTime * 1000, isUtc: true)
          : receivedAt.toUtc().add(Duration(seconds: expireTime));
      if (bound.isBefore(invalidAt)) invalidAt = bound;
    }
    return (refreshAt: invalidAt.subtract(const Duration(seconds: 30)), invalidAt: invalidAt);
  }

  /// The line to use after a refresh (3.x `HuyaTransportPolicy`): matched
  /// by CDN host and port, format and credential family, never by the old
  /// index (REG-HUYA-010). Pools are tried from narrow to wide: native FLV
  /// (only when the current line was native), the same format, all. In a
  /// pool the same CDN and path wins, then the same CDN (a restarted stream
  /// renames the path); [advanceLine] takes the next one in the pool, and a
  /// pool of one widens to the next pool.
  static int selectRefreshedLine({
    required List<String> urls,
    required String? currentUrl,
    required int currentLineIndex,
    required bool advanceLine,
  }) {
    if (urls.isEmpty) return 0;
    final legacyIndex = currentLineIndex.clamp(0, urls.length - 1);
    final fallback = advanceLine ? (legacyIndex + 1) % urls.length : legacyIndex;
    final current = _mediaUri(currentUrl ?? '');
    if (current == null) return fallback;
    final candidates = urls.map(_mediaUri).toList();
    final all = [
      for (var i = 0; i < candidates.length; i++)
        if (candidates[i] != null) i,
    ];
    final isFlv = current.path.toLowerCase().endsWith('.flv');
    final sameFormat = [
      for (final i in all)
        if (candidates[i]!.path.toLowerCase().endsWith('.flv') == isFlv) i,
    ];
    final wasNative = isNativeFlv(current);
    final native = [
      for (final i in sameFormat)
        if (isNativeFlv(candidates[i]!)) i,
    ];
    for (final pool in [if (wasNative) native, sameFormat, all]) {
      if (pool.isEmpty) continue;
      bool sameCdn(int i) =>
          candidates[i]!.host == current.host &&
          candidates[i]!.port == current.port &&
          isNativeFlv(candidates[i]!) == wasNative;
      var position = pool.indexWhere((i) => sameCdn(i) && candidates[i]!.path == current.path);
      if (position < 0) position = pool.indexWhere(sameCdn);
      if (position < 0) return pool.first;
      if (!advanceLine) return pool[position];
      if (pool.length > 1) return pool[(position + 1) % pool.length];
    }
    return fallback;
  }

  static Uri? _mediaUri(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || !_isHuyaHost(uri.host)) return null;
    final path = uri.path.toLowerCase();
    return path.endsWith('.flv') || path.endsWith('.m3u8') ? uri : null;
  }

  // Identity ------------------------------------------------------------------

  /// The account uid: an exact `yyuid=<digits>` cookie field above 0
  /// (`foo=yyuid=12` does not count).
  static int? viewerUidFromCookie(String? cookie) {
    final match = RegExp(r'(?:^|;\s*)yyuid=(\d+)(?:;|$)').firstMatch(cookie?.trim() ?? '');
    final uid = int.tryParse(match?.group(1) ?? '');
    return uid != null && uid > 0 ? uid : null;
  }

  /// A local temporary viewer uid for when anonymous login fails:
  /// 1400000000000 plus a uniform value below 10^11, composed from two
  /// ranges `Random.nextInt` supports (3.x asked for one range above 2^32
  /// and threw RangeError exactly then, REG-HUYA-017).
  static int fallbackViewerUid(Random random) =>
      1400000000000 + random.nextInt(1000000) * 100000 + random.nextInt(100000);

  /// A 32-digit lower-case hexadecimal GUID.
  static String guid(Random random) => List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();

  /// `udblgn.huya.com/web/anonymousLogin` → `data.uid`; null when the
  /// answer has none.
  static int? anonymousUid(String body, {int status = 200}) {
    if (status != 200) return null;
    try {
      final uid = jsonInt(_object(_object(jsonDecode(body))?['data'])?['uid']);
      return uid != null && uid > 0 ? uid : null;
    } on FormatException {
      return null;
    }
  }

  /// `huya.user_agent` of the player configuration
  /// (`assets/play_config.json`), or null. A HYSDK UA naming an older PC
  /// client (`pc_exe&<version>`) than [hysdkUserAgent] is null too, so a
  /// stale file never downgrades the built-in UA.
  static String? playUserAgent(Map<String, Object?>? config) {
    final configured = jsonString(_object(config?['huya'])?['user_agent']);
    if (configured == null || !configured.startsWith('HYSDK(')) return configured;
    final version = _pcExeVersion(configured);
    return version != null && version < _pcExeVersion(hysdkUserAgent)! ? null : configured;
  }

  static int? _pcExeVersion(String userAgent) =>
      int.tryParse(RegExp(r'pc_exe&(\d+)&').firstMatch(userAgent)?.group(1) ?? '');

  /// The numeric room of a room page: `var TT_ROOM_DATA = {...}`'s
  /// `profileRoom`, else the first `"profileRoom"` in the page; null
  /// without one.
  static String? roomIdFromPage(String html) {
    final data = RegExp(r'var\s+TT_ROOM_DATA\s*=\s*(\{.*?\})\s*;', dotAll: true).firstMatch(html);
    if (data != null) {
      try {
        if (_roomId(_object(jsonDecode(data.group(1)!))?['profileRoom']) case final id?) return id;
      } on FormatException {
        // Fall through to the loose match.
      }
    }
    return _roomId(RegExp(r'"profileRoom"\s*:\s*"?(\d+)"?').firstMatch(html)?.group(1));
  }

  // WUP -----------------------------------------------------------------------

  /// `liveui.getCdnTokenInfoEx` with `GetCdnTokenExReq` (tags: 0 sFlvUrl,
  /// 1 sStreamName, 2 iLoopTime, 3 tId, 4 iAppId).
  static Uint8List cdnTokenRequest({
    required String flvUrl,
    required String streamName,
    required HuyaUserId userId,
    int loopTime = 0,
    int appId = tokenAppId,
  }) => WupPacket(
    servant: 'liveui',
    function: 'getCdnTokenInfoEx',
    params: {
      'tReq': WupPacket.structParam(
        (writer) => writer
          ..writeString(0, flvUrl)
          ..writeString(1, streamName)
          ..writeInt(2, loopTime)
          ..writeStruct(3, userId.writeTo)
          ..writeInt(4, appId),
      ),
    },
  ).encode();

  /// The `getCdnTokenInfoEx` answer: the return code, and `GetCdnTokenExResp`
  /// (tag 0 sFlvToken, tag 1 iExpireTime). HTTP 5xx is `NetworkFailure`,
  /// another status or undecodable bytes `ApiChanged`.
  static ({int code, String token, int expireTime}) cdnTokenResponse(List<int> bytes, {int status = 200}) {
    final packet = _wup(bytes, status: status, what: 'getCdnTokenInfoEx');
    final code = packet.code;
    final rsp = _decoded(() => packet.struct('tRsp'), 'getCdnTokenInfoEx');
    if (code == 0 && rsp == null) throw const ApiChanged(_site, 'getCdnTokenInfoEx: no tRsp');
    return (code: code, token: (rsp?.string(0) ?? '').trim(), expireTime: rsp?.integer(1) ?? 0);
  }

  /// `wupui.getHeadLineMessageBoard` for the board of [topSid]
  /// (`GetGameEventMessageBoardReq`: 0 lPid, 1 sOffset, 2 tId with the HYSDK
  /// UA, 3 iMessageBoardScope 0, 4 iPageSize 10).
  static Uint8List messageBoardRequest(int topSid) => WupPacket(
    servant: 'wupui',
    function: 'getHeadLineMessageBoard',
    params: {
      'tReq': WupPacket.structParam(
        (writer) => writer
          ..writeInt(0, topSid)
          ..writeString(1, '')
          ..writeStruct(2, const HuyaUserId(huyaUa: hysdkUserAgent).writeTo)
          ..writeInt(3, 0)
          ..writeInt(4, 10),
      ),
    },
  ).encode();

  /// The headline message board (3.x `getHuyaSuperChatMessageList` with
  /// `first: true`, the only form 3.x called): `tRsp` tag 1 is the panel
  /// (`GameEventMessageBoardPanel`), read as [_panel] reads it. A non-zero
  /// return code is `ApiChanged`.
  static List<LiveSuperChatMessage> superChats(List<int> bytes, {required DateTime now, int status = 200}) {
    final packet = _wup(bytes, status: status, what: 'getHeadLineMessageBoard');
    if (packet.code != 0) throw ApiChanged(_site, 'getHeadLineMessageBoard code ${packet.code}');
    return _panel(_decoded(() => packet.struct('tRsp'), 'getHeadLineMessageBoard')?.struct(1), now: now);
  }

  /// The body of a headline notice (danmaku uri 2001314), which is the
  /// board's panel itself (`GameEventMessageBoardPanel` in the web client's
  /// uri table; appendix C-9): its entries as [superChats] reads them, an
  /// empty list for an empty board. Null when [body] is not a panel
  /// (missing, empty, not Tars, or without the entry list at tag 1): the
  /// caller then fetches the board.
  static List<LiveSuperChatMessage>? headlineNotice(List<int>? body, {required DateTime now}) {
    if (body == null || body.isEmpty) return null;
    final TarsStruct panel;
    try {
      panel = TarsStruct.decode(body);
    } on FormatException {
      return null;
    }
    return panel.fields[1] is List ? _panel(panel, now: now) : null;
  }

  /// The entries of a board panel: tag 1 lists them (0 user: 1 nick, 2
  /// avatar; 1 content; 2 iCost; 4 iTotalSec; 5 iCountDown; 9 lMessageId;
  /// 12 iCostPay).
  ///
  /// Entries without text or time left are dropped. Time left is the
  /// countdown, else the total; the window ends that long after [now] and
  /// starts the total before. The price is iCost, else iCostPay / 100 (at
  /// least 1). The id is `huya:{lMessageId}`, so an event rebuilt on every
  /// poll stays one message.
  static List<LiveSuperChatMessage> _panel(TarsStruct? panel, {required DateTime now}) {
    final messages = <LiveSuperChatMessage>[];
    for (final raw in panel?.list(1) ?? const <Object?>[]) {
      if (raw is! TarsStruct) continue;
      final content = (raw.string(1) ?? '').trim();
      final total = raw.integer(4) ?? 0;
      final countdown = raw.integer(5) ?? 0;
      final remaining = countdown > 0 ? countdown : total;
      if (content.isEmpty || remaining <= 0) continue;
      final cost = raw.integer(2) ?? 0;
      final paid = raw.integer(12) ?? 0;
      final id = raw.integer(9) ?? 0;
      final user = raw.struct(0);
      final end = now.add(Duration(seconds: remaining));
      messages.add(
        LiveSuperChatMessage(
          messageId: id > 0 ? 'huya:$id' : '',
          userName: (user?.string(1) ?? '').trim(),
          face: normalizeImageUrl(user?.string(2)),
          message: content,
          price: cost > 0 ? cost : (paid > 0 ? max(1, (paid / 100).round()) : cost),
          unit: LiveGiftUnit.yuan,
          startTime: end.subtract(Duration(seconds: total > 0 ? total : remaining)),
          endTime: end,
          backgroundColor: '#ffffff',
          backgroundBottomColor: '#246488',
        ),
      );
    }
    return messages;
  }

  static WupPacket _wup(List<int> bytes, {required int status, required String what}) {
    if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
    if (status != 200) throw ApiChanged(_site, '$what: HTTP $status');
    return _decoded(() => WupPacket.decode(bytes), what)!;
  }

  static T? _decoded<T>(T? Function() decode, String what) {
    try {
      return decode();
    } on FormatException catch (error) {
      throw ApiChanged(_site, '$what: ${error.message}');
    }
  }
}

bool _isHuyaHost(String host) {
  final lower = host.toLowerCase();
  return lower == 'huya.com' || lower.endsWith('.huya.com');
}

/// A query split without decoding (tokens may carry stray `%`); the first
/// value of a repeated key wins.
List<({String key, String value, String raw})> _parse(String query) {
  final params = <({String key, String value, String raw})>[];
  final seen = <String>{};
  for (final segment in query.trim().split('&')) {
    if (segment.isEmpty) continue;
    final separator = segment.indexOf('=');
    final key = separator < 0 ? segment : segment.substring(0, separator);
    if (!seen.add(key)) continue;
    params.add((key: key, value: separator < 0 ? '' : segment.substring(separator + 1), raw: segment));
  }
  return params;
}

Map<String, String> _parseMap(String query) => {for (final param in _parse(query)) param.key: param.value};

/// `wsTime`: hexadecimal Unix seconds; null when missing or invalid.
DateTime? _wsTime(String? value) {
  final seconds = int.tryParse(value?.trim() ?? '', radix: 16);
  if (seconds == null || seconds <= 0 || seconds > 0xFFFFFFFFFF) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

DateTime? _earliest(Iterable<DateTime?> values) {
  DateTime? result;
  for (final value in values) {
    if (value != null && (result == null || value.isBefore(result))) result = value;
  }
  return result;
}

/// A room id: a non-negative integer (`102411.0` too) as decimal text.
String? _roomId(Object? value) {
  final id = jsonInt(value);
  return id != null && id > 0 ? '$id' : null;
}

int? _positive(Object? value) => switch (jsonInt(value)) {
  final int number when number > 0 => number,
  _ => null,
};

/// A 0/1 or boolean flag (`isRoomPay` is `false` in `profileRoom` and `"0"`
/// in lists); null when absent or anything else.
bool? _flag(Object? value) => switch (value) {
  final bool flag => flag,
  'true' => true,
  'false' => false,
  _ => switch (jsonInt(value)) {
    1 => true,
    0 => false,
    _ => null,
  },
};

/// Text as 3.x wrote it (not trimmed), HTML entities decoded; '' for null.
String _text(Object? value) => value == null ? '' : decodeHtmlEntities('$value');

/// The introduction, else the room name.
String _title(Object? introduction, Object? roomName) => _text(introduction).ifEmpty(() => _text(roomName));

/// A count as 3.x wrote it; integral numbers without a fraction.
String _count(Object? value) => switch (value) {
  null => '',
  final num number => jsonInt(number)?.toString() ?? '$number',
  _ => '$value'.trim(),
};

/// A list or search cover: a screenshot without a query gets the thumbnail
/// style (3.x also did this to a missing one, giving `null?x-oss…`).
String _thumbnail(Object? value) {
  final url = normalizeImageUrl(value);
  if (url.isEmpty || url.contains('?')) return url;
  return '$url?x-oss-process=style/w338_h190&';
}

extension on String {
  String ifEmpty(String Function() other) => isEmpty ? other() : this;
}

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// The decoded JSON object of a response: HTTP 429 is `RateLimited`, 5xx
/// `NetworkFailure`, another non-2xx or a body that is not an object
/// `ApiChanged`. Huya reports its own errors inside a 200 body.
Map<String, dynamic> _json(String body, {required int status, required String what}) {
  if (status == 429) throw RateLimited(_site, detail: '$what: HTTP 429');
  if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
  if (status < 200 || status >= 300) throw ApiChanged(_site, '$what: HTTP $status');
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  if (decoded is! Map<String, dynamic>) throw ApiChanged(_site, '$what: not a JSON object (${_snippet(body)})');
  return decoded;
}

/// A `cache.php` or `bussLive` envelope: [_json] with `status` 200.
Map<String, dynamic> _envelope(String body, {required int status, required String what}) {
  final root = _json(body, status: status, what: what);
  final code = jsonInt(root['status']);
  if (code != 200) {
    throw ApiChanged(
      _site,
      '$what: status $code ${jsonString(root['message']) ?? jsonString(root['msg']) ?? ''}'.trim(),
    );
  }
  return root;
}
