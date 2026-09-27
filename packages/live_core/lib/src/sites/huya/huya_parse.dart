import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/huya/huya_stream.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

export 'package:live_core/src/sites/huya/huya_stream.dart';

const _site = 'huya';
const _web = 'https://www.huya.com';

/// Rank of the source quality (bit rate 0), above every transcode (§5.1).
const int _sourceRank = 1 << 30;

/// Pure parsing of Huya responses (spec/sites/huya.md). Every function takes
/// the raw response text the adapter received (and its HTTP status) and either
/// returns domain values or throws a `SiteError`. Signing (md5), WUP and the
/// viewer identity stay in the adapter.
abstract final class HuyaParse {
  /// The HYSDK User-Agent shipped with the adapter; media requests and the
  /// native WUP request use the same value (§6.5).
  static const mediaUserAgent = 'HYSDK(Windows,30000002)_APP(pc_exe&7090000&official)_SDK(trans&2.35.0.5996)';

  /// §2.1 the four fixed top-level categories, in platform order.
  static const topCategories = <({String id, String name})>[
    (id: '1', name: '网游'),
    (id: '2', name: '单机'),
    (id: '8', name: '娱乐'),
    (id: '3', name: '手游'),
  ];

  static Object? _json(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  static Map<String, dynamic> _map(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    throw ApiChanged(_site, '$what: expected an object');
  }

  static List<dynamic> _list(Object? value, String what) {
    if (value is List) return value;
    throw ApiChanged(_site, '$what: expected a list');
  }

  /// Maps a non-200 HTTP status; Huya reports its own errors in a 200 body.
  static void _checkHttp(int status, String what) {
    if (status == 200) return;
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status');
    throw ApiChanged(_site, '$what HTTP $status');
  }

  /// The body of a `bussLive` or `cache.php` response: an object whose
  /// `status` is 200.
  static Map<String, dynamic> _root(String body, int status, String what) {
    _checkHttp(status, what);
    final root = _map(_json(body, what), what);
    final code = jsonInt(root['status']);
    if (code != 200) throw ApiChanged(_site, '$what status $code: ${jsonString(root['message'] ?? root['msg']) ?? ''}');
    return root;
  }

  /// A room id as text: integral numbers (`102411.0` too) without a fraction.
  static String? _id(Object? value) => value is num ? jsonInt(value)?.toString() : jsonString(value);

  static RoomRef? _ref(Object? value) {
    final id = _id(value);
    if (id == null) return null;
    try {
      return RoomRef(_site, id);
    } on FormatException {
      return null;
    }
  }

  static int? _positive(Object? value) {
    final number = jsonInt(value);
    return number != null && number > 0 ? number : null;
  }

  static String _text(Object? value) => decodeHtmlEntities(jsonString(value) ?? '');

  static String? _optionalText(Object? value) {
    final text = jsonString(value);
    return text == null ? null : decodeHtmlEntities(text);
  }

  /// §2.2 / §3 / §4.2 the title is the introduction, else the room name.
  static String _title(Object? introduction, Object? roomName) =>
      decodeHtmlEntities(jsonString(introduction) ?? jsonString(roomName) ?? '');

  /// §2.2 list and search covers: a screenshot without a query gets the
  /// thumbnail style.
  static Uri? _thumbnail(Object? value) {
    final text = jsonString(value);
    if (text == null) return null;
    return jsonUrl(text.contains('?') ? text : '$text?x-oss-process=style/w338_h190&');
  }

  static bool _isHuyaHost(String host) {
    final lower = host.toLowerCase();
    return lower == 'huya.com' || lower.endsWith('.huya.com');
  }

  /// Splits a query without decoding it (tokens may carry stray `%`); the first
  /// value of a repeated key wins.
  static Map<String, String> _query(String query) {
    final result = <String, String>{};
    for (final segment in query.split('&')) {
      if (segment.isEmpty) continue;
      final separator = segment.indexOf('=');
      final key = separator < 0 ? segment : segment.substring(0, separator);
      result.putIfAbsent(key, () => separator < 0 ? '' : segment.substring(separator + 1));
    }
    return result;
  }

  static String _key(String segment) {
    final separator = segment.indexOf('=');
    return separator < 0 ? segment : segment.substring(0, separator);
  }

  /// `wsTime` is hexadecimal epoch seconds; null when missing or invalid.
  static DateTime? _wsTime(String? value) {
    final seconds = int.tryParse(value?.trim() ?? '', radix: 16);
    if (seconds == null || seconds <= 0 || seconds > 0xFFFFFFFFFF) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static DateTime? _earliest(Iterable<DateTime?> values) {
    DateTime? result;
    for (final value in values) {
      if (value != null && (result == null || value.isBefore(result))) result = value;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Catalog

  /// §2.1 `bussLive?bussType=<id>` → that top-level category with its areas,
  /// in server order. `gid` may be written as `2165.0`.
  static Category category(String body, {required String id, int status = 200}) {
    final name = topCategories.where((category) => category.id == id).firstOrNull?.name;
    if (name == null) throw ArgumentError.value(id, 'id', 'not a Huya top-level category');
    final root = _root(body, status, 'bussLive');
    final areas = <Area>[];
    for (final item in _list(root['data'], 'bussLive.data')) {
      final gid = item is Map ? _positive(item['gid']) : null;
      if (gid == null) continue;
      areas.add(
        Area(
          id: '$gid',
          name: _text((item as Map)['gameFullName']),
          categoryId: id,
          icon: Uri.parse('https://huyaimg.msstatic.com/cdnimage/game/$gid-MS.jpg'),
        ),
      );
    }
    return Category(id: id, name: name, areas: areas);
  }

  /// §2.2 / §2.3 `getLiveListByPage` (recommended without `gameId`, an area
  /// with it). Every listed room is live; popularity is `totalCount`. The page
  /// ends at `data.totalPage` or on an empty `datas`, never by the count.
  static Page<RoomCard> roomListPage(String body, {required int page, int status = 200}) {
    final root = _root(body, status, 'getLiveListByPage');
    final data = _map(root['data'], 'getLiveListByPage.data');
    final raw = _list(data['datas'], 'getLiveListByPage.data.datas');
    final rooms = <RoomCard>[
      for (final item in raw)
        if (item is Map && _ref(item['profileRoom']) != null)
          RoomCard(
            ref: _ref(item['profileRoom'])!,
            title: _title(item['introduction'], item['roomName']),
            anchorName: _text(item['nick']),
            state: LiveState.live,
            cover: _thumbnail(item['screenshot']),
            area: _optionalText(item['gameFullName']),
            audience: Audience(popularity: jsonInt(item['totalCount'])),
          ),
    ];
    final totalPage = jsonInt(data['totalPage']) ?? 0;
    final more = raw.isNotEmpty && (totalPage <= 0 || page < totalPage);
    return Page(rooms, next: more ? PageCursor('${page + 1}') : null);
  }

  // ---------------------------------------------------------------------------
  // Search

  /// §3 `getSearchContent` (`v=4`, live rooms only) for the request's
  /// [start] and [rows]; the cursor is the next `start`.
  ///
  /// The API answers a later page with every result from the first one again
  /// (S04-page2: 40 docs for `start=20&rows=20`; DIAGNOSIS). When `docs` holds
  /// more than [rows] entries, the first [start] are the earlier pages and are
  /// skipped; a room seen earlier in the same response is never repeated.
  /// The room id comes from the streamer entry (`response.1`) with the same
  /// `uid` and `yyid`, else from the room entry. The last page is the one that
  /// reaches `numFound` or has no new entries.
  static Page<RoomCard> searchPage(String body, {required int start, required int rows, int status = 200}) {
    _checkHttp(status, 'getSearchContent');
    final root = _map(_json(body, 'getSearchContent'), 'getSearchContent');
    final response = _map(root['response'], 'getSearchContent.response');
    final live = _map(response['3'], 'getSearchContent.response.3');
    final docs = _list(live['docs'], 'getSearchContent.response.3.docs');
    final streamers = response['1'] is Map ? (response['1'] as Map)['docs'] : null;

    String? roomIdOf(Map<dynamic, dynamic> doc) {
      final uid = jsonString(doc['uid']);
      final yyid = jsonString(doc['yyid']);
      if (uid != null && yyid != null && streamers is List) {
        for (final streamer in streamers) {
          if (streamer is Map && jsonString(streamer['uid']) == uid && jsonString(streamer['yyid']) == yyid) {
            final id = _id(streamer['room_id']);
            if (id != null) return id;
          }
        }
      }
      return _id(doc['room_id']);
    }

    final skipped = docs.length > rows ? (start < docs.length ? start : docs.length) : 0;
    final seen = <String>{};
    final rooms = <RoomCard>[];
    for (final (index, doc) in docs.indexed) {
      if (doc is! Map) continue;
      final ref = _ref(roomIdOf(doc));
      if (ref == null) continue;
      final fresh = seen.add(ref.roomId);
      if (index < skipped || !fresh) continue;
      rooms.add(
        RoomCard(
          ref: ref,
          title: _title(doc['game_introduction'], doc['game_roomName']),
          anchorName: _text(doc['game_nick']),
          state: LiveState.live,
          cover: _thumbnail(doc['game_screenshot']),
          area: _optionalText(doc['gameName']),
          audience: Audience(popularity: jsonInt(doc['game_total_count'])),
        ),
      );
    }
    final numFound = jsonInt(live['numFound']);
    final end = start + rows;
    final more = docs.length > skipped && (numFound == null || end < numFound);
    return Page(rooms, next: more ? PageCursor('$end') : null);
  }

  // ---------------------------------------------------------------------------
  // Room detail

  /// §4.2 / §9 the `data` object of a `profileRoom` response. `status: 422`
  /// ("该主播不存在！", also for a letter alias) is NotFound; any other status
  /// but 200 is ApiChanged.
  static Map<String, dynamic> _profile(String body, int status) {
    _checkHttp(status, 'profileRoom');
    final root = _map(_json(body, 'profileRoom'), 'profileRoom');
    final code = jsonInt(root['status']);
    if (code == 422) throw NotFound(_site, 'profileRoom 422: ${jsonString(root['message']) ?? ''}');
    if (code != 200) throw ApiChanged(_site, 'profileRoom status $code');
    return _map(root['data'], 'profileRoom.data');
  }

  /// §4.2 `liveStatus`, trimmed and upper-cased. ADR 0010 has no "unknown"
  /// state, so any other value is ApiChanged (never offline).
  static LiveState _liveState(Object? value) => switch (jsonString(value)?.toUpperCase()) {
    'ON' => LiveState.live,
    'REPLAY' => LiveState.replay,
    'OFF' || 'OFFLINE' || 'CLOSED' => LiveState.offline,
    final other => throw ApiChanged(_site, 'profileRoom liveStatus ${other ?? 'missing'}'),
  };

  /// §1 topSid / subSid: the first positive `lChannelId` / `lSubChannelId` in
  /// `stream.baseSteamInfoList` (whether or not `multiLine` lists the CDN),
  /// else `data.chTopId` / `data.subChId`.
  static (int?, int?) _channels(Map<String, dynamic> data) {
    final stream = data['stream'];
    final bases = stream is Map && stream['baseSteamInfoList'] is List
        ? (stream['baseSteamInfoList'] as List).whereType<Map<dynamic, dynamic>>()
        : const <Map<dynamic, dynamic>>[];
    int? first(String key) => bases.map((base) => _positive(base[key])).nonNulls.firstOrNull;
    return (first('lChannelId') ?? _positive(data['chTopId']), first('lSubChannelId') ?? _positive(data['subChId']));
  }

  /// §4 `profileRoom` detail for live, offline and replay rooms. The room id
  /// is the response's `profileRoom` (normalised), else [roomId]. Every count
  /// is popularity (§4.3): `totalCount`, else `userCount`.
  static RoomDetail detail(String body, {int status = 200, String? roomId}) {
    final data = _profile(body, status);
    final state = _liveState(data['liveStatus']);
    final profile = _map(data['profileInfo'], 'profileRoom.data.profileInfo');
    final live = _map(data['liveData'], 'profileRoom.data.liveData');
    final ref = _ref(profile['profileRoom']) ?? _ref(live['profileRoom']) ?? _ref(roomId);
    if (ref == null) throw const ApiChanged(_site, 'profileRoom: no room id');
    final uid = _positive(profile['uid']) ?? _positive(live['uid']);
    final (topSid, subSid) = _channels(data);
    return RoomDetail(
      card: RoomCard(
        ref: ref,
        title: _title(live['introduction'], live['roomName']),
        anchorName: _text(profile['nick'] ?? live['nick']),
        state: state,
        cover: jsonUrl(live['screenshot']),
        area: _optionalText(live['gameFullName']),
        audience: Audience(popularity: jsonInt(live['totalCount']) ?? jsonInt(live['userCount'])),
      ),
      link: Uri.parse('$_web/${ref.roomId}'),
      avatar: jsonUrl(profile['avatar180']) ?? jsonUrl(live['avatar180']),
      introduction: _optionalText(live['introduction']),
      notice: _optionalText(data['welcomeText']),
      danmakuKeys: {
        if (uid != null) 'uid': '$uid',
        if (topSid != null) 'topSid': '$topSid',
        if (subSid != null) 'subSid': '$subSid',
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Streams

  /// §4.2 / §6.1 the `data` of a `profileRoom` response re-requested to play.
  /// A room that is not `ON`, or `ON` without `stream`, is StreamUnavailable.
  static Map<String, dynamic> playData(String body, {int status = 200}) {
    final data = _profile(body, status);
    final state = _liveState(data['liveStatus']);
    if (state != LiveState.live) throw StreamUnavailable(_site, 'profileRoom: room is ${state.name}');
    if (data['stream'] is! Map) throw const StreamUnavailable(_site, 'profileRoom: ON without stream');
    return data;
  }

  /// §5.1 the rate list: `liveData.bitRateInfo` (a JSON string or a list),
  /// else `stream.flv.rateArray` when it is missing or not a list.
  static List<dynamic> _rates(Map<String, dynamic> data) {
    final live = data['liveData'];
    var info = live is Map ? live['bitRateInfo'] : null;
    if (info is String) {
      try {
        info = info.trim().isEmpty ? null : jsonDecode(info);
      } on FormatException {
        info = null;
      }
    }
    if (info is List) return info;
    final stream = data['stream'];
    final flv = stream is Map ? stream['flv'] : null;
    final rateArray = flv is Map ? flv['rateArray'] : null;
    return rateArray is List ? rateArray : const [];
  }

  /// §5.1 qualities: id is the bit rate (`0` is the source), entries with a
  /// blank name or a negative rate are dropped, the first of a rate wins; the
  /// source first, then by rate descending. No rates → one "原画" at 0.
  static List<Quality> qualities(Map<String, dynamic> data) {
    final seen = <int>{};
    final qualities = <Quality>[];
    for (final item in _rates(data)) {
      if (item is! Map) continue;
      final name = jsonString(item['sDisplayName']);
      final rate = jsonInt(item['iBitRate']);
      if (name == null || rate == null || rate < 0 || !seen.add(rate)) continue;
      qualities.add(Quality(id: '$rate', label: decodeHtmlEntities(name), rank: rate == 0 ? _sourceRank : rate));
    }
    if (qualities.isEmpty) return const [Quality(id: '0', label: '原画', rank: _sourceRank)];
    return qualities..sort((a, b) => b.rank.compareTo(a.rank));
  }

  /// [requested] when offered (matched by id), else the best quality.
  static Quality selectQuality(List<Quality> qualities, Quality? requested) =>
      qualities.where((quality) => quality.id == requested?.id).firstOrNull ?? qualities.first;

  /// §5.2 an `http://` base on a huya.com host becomes `https://`; other hosts
  /// stay as they are.
  static Uri secureBase(Uri base) =>
      base.scheme == 'http' && _isHuyaHost(base.host) ? base.replace(scheme: 'https') : base;

  /// §5.2 lines: `stream.flv.multiLine` then `stream.hls.multiLine` in server
  /// order, entries with a non-empty `url` whose `cdnType` matches a
  /// `baseSteamInfoList[].sCdnType`. Base entries that `multiLine` does not
  /// list (AL13 with priority −1) are left out. No line is StreamUnavailable
  /// (§9; a live room without `multiLine`, DIAGNOSIS).
  static List<HuyaLine> lines(Map<String, dynamic> data) {
    final stream = _map(data['stream'], 'profileRoom.data.stream');
    final bases = stream['baseSteamInfoList'] is List
        ? (stream['baseSteamInfoList'] as List).whereType<Map<dynamic, dynamic>>().toList()
        : const <Map<dynamic, dynamic>>[];
    final profile = data['profileInfo'];
    final profileUid = profile is Map ? _positive(profile['uid']) : null;
    final lines = <HuyaLine>[];
    final seen = <String>{};
    for (final (format, key, urlKey, codeKey) in const [
      (StreamFormat.flv, 'flv', 'sFlvUrl', 'sFlvAntiCode'),
      (StreamFormat.hls, 'hls', 'sHlsUrl', 'sHlsAntiCode'),
    ]) {
      final group = stream[key];
      final multiLine = group is Map ? group['multiLine'] : null;
      for (final item in multiLine is List ? multiLine : const <Object?>[]) {
        if (item is! Map || jsonString(item['url']) == null) continue;
        final cdn = jsonString(item['cdnType']);
        final base = cdn == null ? null : bases.where((base) => jsonString(base['sCdnType']) == cdn).firstOrNull;
        final baseUrl = base == null ? null : jsonUrl(base[urlKey]);
        final name = base == null ? null : jsonString(base['sStreamName']);
        if (baseUrl == null || name == null || !seen.add('${format.name}:$cdn')) continue;
        lines.add(
          HuyaLine(
            cdnType: cdn!,
            format: format,
            base: secureBase(baseUrl),
            streamName: name,
            antiCode: jsonString(base![codeKey]) ?? '',
            presenterUid: _positive(base['lPresenterUid']) ?? profileUid ?? _positive(base['lChannelId']),
          ),
        );
      }
    }
    if (lines.isEmpty) throw const StreamUnavailable(_site, 'profileRoom: no multiLine entry with a stream');
    return lines;
  }

  /// §5.1 / §5.2 / §6.4 step 10 the media URL
  /// `{base}/{streamName}.{flv|m3u8}?{antiCode}` for [quality]: `codec=264`
  /// is added when absent, `ratio` is set to the bit rate (removed for the
  /// source). [antiCode] is the signed query or a static token; a template
  /// still carrying `fm` is refused, since the CDN rejects it.
  static Uri mediaUrl(HuyaLine line, {required String antiCode, required Quality quality}) {
    final segments = [
      for (final segment in antiCode.trim().split('&'))
        if (segment.isNotEmpty) segment,
    ];
    // The token must not end up in an error message (§6.7).
    if (segments.isEmpty) throw ArgumentError('Huya ${line.format.name} token is empty');
    if (segments.any((segment) => _key(segment) == 'fm')) throw ArgumentError('Huya AntiCode is unsigned (fm)');
    if (!segments.any((segment) => _key(segment) == 'codec')) segments.add('codec=264');
    final rate = int.tryParse(quality.id) ?? 0;
    final query = <String>[];
    var ratio = false;
    for (final segment in segments) {
      if (_key(segment) != 'ratio') {
        query.add(segment);
      } else if (!ratio) {
        ratio = true;
        if (rate > 0) query.add('ratio=$rate');
      }
    }
    if (!ratio && rate > 0) query.add('ratio=$rate');
    final base = line.base.toString();
    final left = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final extension = line.format == StreamFormat.flv ? 'flv' : 'm3u8';
    return Uri.parse('$left/${line.streamName}.$extension?${query.join('&')}');
  }

  /// §6.5 media request headers, the same for playing and recording; no
  /// cookie is sent to the CDN.
  static Map<String, String> mediaHeaders(String roomId) => {
    'user-agent': mediaUserAgent,
    'origin': _web,
    'referer': '$_web/$roomId',
  };

  /// A playable line for [url] built at [builtAt] from [line]. Huya does not
  /// report the delivered quality, so `confirmed` stays null (§5.1). [token]
  /// is the WUP token window when the URL was signed from one.
  static StreamLine streamLine(
    HuyaLine line, {
    required Uri url,
    required Quality requested,
    required String roomId,
    required DateTime builtAt,
    HuyaTokenWindow? token,
  }) => StreamLine(
    url: url,
    format: line.format,
    lineId: line.cdnType,
    requested: requested,
    headers: mediaHeaders(roomId),
    codec: switch (_query(url.query)['codec']) {
      '264' => 'avc',
      '265' => 'hevc',
      _ => null,
    },
    lease: lease(url, builtAt: builtAt, token: token),
  );

  // ---------------------------------------------------------------------------
  // Leases

  /// §6.2 / §6.6 the window of a WUP `getCdnTokenInfoEx` token received at
  /// [receivedAt]: valid until `wsTime + 300 s`, earlier when `iExpireTime`
  /// says so (above 10^12 a millisecond timestamp, above 10^9 a second
  /// timestamp, else seconds after [receivedAt]); refreshed 30 s before. An
  /// empty token or one without a hexadecimal `wsTime` is ApiChanged.
  static HuyaTokenWindow tokenWindow(String token, {required int expireTime, required DateTime receivedAt}) {
    if (token.trim().isEmpty) throw const ApiChanged(_site, 'getCdnTokenInfoEx: empty sFlvToken');
    final wsTime = _wsTime(_query(token.trim())['wsTime']);
    if (wsTime == null) throw const ApiChanged(_site, 'getCdnTokenInfoEx: sFlvToken without wsTime');
    var invalidAt = wsTime.add(const Duration(seconds: 300));
    // Tars iExpireTime is an int32; anything beyond a millisecond timestamp is noise.
    if (expireTime > 0 && expireTime < 8640000000000000) {
      final bound = expireTime > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(expireTime, isUtc: true)
          : expireTime > 1000000000
          ? DateTime.fromMillisecondsSinceEpoch(expireTime * 1000, isUtc: true)
          : receivedAt.toUtc().add(Duration(seconds: expireTime));
      if (bound.isBefore(invalidAt)) invalidAt = bound;
    }
    return HuyaTokenWindow(refreshAt: invalidAt.subtract(const Duration(seconds: 30)), invalidAt: invalidAt);
  }

  /// §5.3 native signed FLV: a huya.com `.flv` with `ctype=huya_pc_exe` and
  /// `t=100`.
  static bool isNativeFlv(Uri url) {
    final query = _query(url.query);
    return _isHuyaHost(url.host) &&
        url.path.toLowerCase().endsWith('.flv') &&
        query['ctype'] == 'huya_pc_exe' &&
        query['t'] == '100';
  }

  /// §6.4 step 6 `u = rotl64(uid)`: the low 32 bits rotate left by 8, the
  /// high 32 bits stay (REG-HUYA-008).
  static int rotateUid(int uid) {
    final low = uid & 0xFFFFFFFF;
    return (uid - low) | (((low << 8) | (low >> 24)) & 0xFFFFFFFF);
  }

  /// The inverse of [rotateUid].
  static int unrotateUid(int value) {
    final low = value & 0xFFFFFFFF;
    return (value - low) | (((low >> 8) | (low << 24)) & 0xFFFFFFFF);
  }

  /// §6.6 when a web-signed URL was issued: `seqid − UID`, where the UID is
  /// `u` rotated back, or `uid` for WAP (`t=103`); null without a plausible
  /// value.
  static DateTime? signedIssuedAt(Uri url) {
    final query = _query(url.query);
    final wap = query['t'] == '103';
    final seqId = int.tryParse(query['seqid'] ?? '');
    final encoded = int.tryParse(query[wap ? 'uid' : 'u'] ?? '');
    if (seqId == null || encoded == null) return null;
    final millis = seqId - (wap ? encoded : unrotateUid(encoded));
    if (millis < DateTime.utc(2020).millisecondsSinceEpoch || millis > DateTime.utc(2100).millisecondsSinceEpoch) {
      return null;
    }
    final issuedAt = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    final signedInvalidAt = _wsTime(query['wsTime'])?.add(const Duration(seconds: 300));
    return signedInvalidAt != null && issuedAt.isAfter(signedInvalidAt) ? null : issuedAt;
  }

  /// §6.6 the lease of a media [url] built at [builtAt]; null for a URL that
  /// is not a Huya `.flv` or `.m3u8`.
  ///
  /// - Native signed FLV: valid until `min(wsTime + 300 s, token)`, refreshed
  ///   30 s before; expiry does not cut the established connection, so the
  ///   player only prefetches.
  /// - Web FLV (static tokens too) and HLS: issued at [signedIssuedAt], else
  ///   [builtAt]; refresh at `min(issued + 100 s, wsTime + 270 s, token)`,
  ///   invalid at `min(issued + 125 s, wsTime + 300 s, token)`; expiry cuts
  ///   the connection.
  static Lease? lease(Uri url, {required DateTime builtAt, HuyaTokenWindow? token}) {
    final path = url.path.toLowerCase();
    if (!_isHuyaHost(url.host) || !(path.endsWith('.flv') || path.endsWith('.m3u8'))) return null;
    final signedInvalidAt = _wsTime(_query(url.query)['wsTime'])?.add(const Duration(seconds: 300));
    if (isNativeFlv(url)) {
      final invalidAt = _earliest([signedInvalidAt, token?.invalidAt]);
      if (invalidAt == null) return null;
      return Lease(
        refreshAt: invalidAt.subtract(const Duration(seconds: 30)),
        expiresAt: invalidAt,
        cutsConnection: false,
      );
    }
    final issuedAt = signedIssuedAt(url) ?? builtAt.toUtc();
    return Lease(
      refreshAt: _earliest([
        issuedAt.add(const Duration(seconds: 100)),
        signedInvalidAt?.subtract(const Duration(seconds: 30)),
        token?.refreshAt,
      ])!,
      expiresAt: _earliest([issuedAt.add(const Duration(seconds: 125)), signedInvalidAt, token?.invalidAt]),
      cutsConnection: true,
    );
  }
}
