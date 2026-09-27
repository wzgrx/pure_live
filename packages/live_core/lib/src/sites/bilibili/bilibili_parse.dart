import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

part 'bilibili_session.dart';

const _site = 'bilibili';

/// Pure parsing of Bilibili responses (spec/sites/bilibili.md). Every function
/// takes the raw response text (and the HTTP status where it matters) and
/// either returns domain values or throws a `SiteError`.
///
/// Session plumbing (buvid, WBI keys, danmaku credentials, QR login, account)
/// is in [BilibiliSession]. Hashing (the WBI `w_rid` md5) is not here: the
/// adapter (`BilibiliSite.wbiSign`) hashes [BilibiliSession.wbiQuery] +
/// [BilibiliSession.mixinKey].
abstract final class BilibiliParse {
  /// Desktop Chrome 138, the UA of every Bilibili request (§6.3).
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/138.0.0.0 Safari/537.36';

  /// How long before `expires` a line is renewed (§6.5, see [lease]).
  static const leaseLead = Duration(seconds: 60);

  /// §2.1 `room/v1/Area/getList`: categories and areas in platform order.
  /// Area icons get the `@100w.png` size suffix.
  static List<Category> categories(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'Area/getList');
    final data = root['data'];
    if (data is! List) throw ApiChanged(_site, 'Area/getList: data is not a list (${_snippet(body)})');
    return [
      for (final raw in data)
        if (raw is Map<String, dynamic> && jsonString(raw['id']) != null)
          Category(
            id: jsonString(raw['id'])!,
            name: decodeHtmlEntities(jsonString(raw['name']) ?? ''),
            areas: [
              for (final area in _list(raw['list']))
                if (area is Map<String, dynamic> && jsonString(area['id']) != null)
                  Area(
                    id: jsonString(area['id'])!,
                    name: decodeHtmlEntities(jsonString(area['name']) ?? ''),
                    categoryId: jsonString(area['parent_id']) ?? jsonString(raw['id'])!,
                    icon: _image(area['pic'], '@100w.png'),
                  ),
            ],
          ),
    ];
  }

  /// §2.2 `second/getList` (WBI signed). Every room is live; the page is
  /// re-sorted by popularity, ties by room identity. The page ends when
  /// `has_more` says so; without `has_more`, an empty page ends it.
  static Page<RoomCard> areaRoomsPage(String body, {required int page, int status = 200}) {
    final root = _checked(body, status: status, what: 'second/getList');
    final data = _object(root['data']);
    final raw = data?['list'] ?? const <Object?>[];
    if (data == null || raw is! List) throw ApiChanged(_site, 'second/getList: no data.list (${_snippet(body)})');
    final rooms = _byPopularity([
      for (final item in raw)
        if (item is Map<String, dynamic>) ?_listCard(item),
    ]);
    final flag = data['has_more'];
    final hasMore = flag is bool ? flag : (jsonInt(flag) == null ? null : jsonInt(flag) != 0);
    final more = raw.isNotEmpty && (hasMore ?? true);
    return Page(rooms, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §2.3 `getListByAreaID` (list in `data`) and its fallback `getMoreRecList`
  /// (list in `data.recommend_room_list`). Every room is live; the page is
  /// sorted by popularity (stable). Neither endpoint reports an end, so an
  /// empty page is the last one.
  static Page<RoomCard> recommendPage(String body, {required int page, int status = 200}) {
    final root = _checked(body, status: status, what: 'recommend');
    final data = root['data'];
    final raw = data is Map<String, dynamic> ? data['recommend_room_list'] : data;
    if (raw is! List) throw ApiChanged(_site, 'recommend: no room list (${_snippet(body)})');
    final rooms = _byPopularity([
      for (final item in raw)
        if (item is Map<String, dynamic>) ?_listCard(item),
    ]);
    return Page(rooms, next: raw.isEmpty ? null : PageCursor('${page + 1}'));
  }

  /// §3 `search/type?search_type=live`.
  ///
  /// `live_room` entries are rooms. `live_user` entries are streamers whose
  /// name matched (DIAGNOSIS: legacy ignored them, so offline and replay
  /// streamers never showed up); they become cards with the streamer's room,
  /// state and area, an empty title and no cover or audience, after the rooms
  /// and only when their room is not already listed. The platform returns the
  /// same `live_user` entries for every page, so they are taken from page 1
  /// only. Paging follows `pageinfo.live_room.numPages`, with an empty
  /// `live_room` page as the fallback end.
  static Page<RoomCard> searchPage(String body, {required int page, int status = 200}) {
    final root = _checked(body, status: status, what: 'search');
    final data = _object(root['data']);
    if (data == null) throw ApiChanged(_site, 'search: no data (${_snippet(body)})');
    final result = _object(data['result']);
    final rawRooms = _list(result?['live_room']);
    final cards = <RoomCard>[
      for (final item in rawRooms)
        if (item is Map<String, dynamic>) ?_searchRoom(item),
    ];
    if (page <= 1) {
      final listed = {for (final card in cards) card.ref};
      for (final item in _list(result?['live_user'])) {
        final card = item is Map<String, dynamic> ? _searchUser(item) : null;
        if (card != null && listed.add(card.ref)) cards.add(card);
      }
    }
    final pages = jsonInt(_object(_object(data['pageinfo'])?['live_room'])?['numPages']);
    final more = rawRooms.isNotEmpty && (pages == null || page < pages);
    return Page(cards, next: more ? PageCursor('${page + 1}') : null);
  }

  /// §4 `getInfoByRoom` (WBI signed). The ref is the canonical long room id
  /// (`room_info.room_id`) whatever id was requested (short id 6 → 7734200).
  /// `live_status` 1 is live, 0 offline, 2 replay (a loop); anything else is
  /// [ApiChanged]. Codes 19002000 (recorded), 60004 and -404 are [NotFound].
  static RoomDetail detail(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'getInfoByRoom', notFound: const {-404, 19002000, 60004});
    final data = _object(root['data']);
    final room = _object(data?['room_info']);
    final anchor = _object(data?['anchor_info']);
    if (data == null || room == null || anchor == null) {
      throw ApiChanged(_site, 'getInfoByRoom: room_info or anchor_info missing (${_snippet(body)})');
    }
    final id = _roomId(room['room_id']);
    if (id == null) throw const ApiChanged(_site, 'getInfoByRoom: room_info.room_id missing');
    final state = switch (jsonInt(room['live_status'])) {
      0 => LiveState.offline,
      1 => LiveState.live,
      2 => LiveState.replay,
      final other => throw ApiChanged(_site, 'getInfoByRoom: live_status $other'),
    };
    final base = _object(anchor['base_info']);
    final started = jsonInt(room['live_start_time']) ?? 0;
    final notice = jsonString(_object(data['news_info'])?['content']);
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, id),
        title: decodeHtmlEntities(jsonString(room['title']) ?? ''),
        anchorName: decodeHtmlEntities(jsonString(base?['uname']) ?? ''),
        state: state,
        cover: _image(room['cover']),
        area: jsonString(room['area_name']),
        audience: _audience(room['online'], data['watched_show'], state),
        liveSince: state == LiveState.live && started > 0
            ? DateTime.fromMillisecondsSinceEpoch(started * 1000, isUtc: true)
            : null,
      ),
      link: Uri.parse('https://live.bilibili.com/$id'),
      avatar: _image(base?['face'], '@100w.jpg'),
      introduction: _richText(room['description']),
      notice: notice == null ? null : decodeHtmlEntities(notice),
      danmakuKeys: {'roomId': id},
    );
  }

  /// §6.1 `getRoomPlayInfo` → its `data` object. `playurl_info: null` (an
  /// offline room, or a replay room: DIAGNOSIS) is [StreamUnavailable]; a
  /// `playurl_info` without `playurl` is [ApiChanged].
  static Map<String, dynamic> playData(String body, {int status = 200}) {
    final root = _checked(body, status: status, what: 'getRoomPlayInfo');
    final data = _object(root['data']);
    if (data == null) throw ApiChanged(_site, 'getRoomPlayInfo: no data (${_snippet(body)})');
    final info = data['playurl_info'];
    if (info == null) {
      throw StreamUnavailable(_site, 'getRoomPlayInfo: playurl_info null, live_status ${data['live_status']}');
    }
    _playurl(data);
    return data;
  }

  /// §5.1 qualities: the union of every codec's `accept_qn` and `current_qn`,
  /// positive only, best first. Never `g_qn_desc` alone: it lists tiers no
  /// codec serves (REG-BILIBILI-002). Labels come from the fixed table, then
  /// `g_qn_desc`, then "清晰度 {qn}"; rank is the qn.
  static List<Quality> qualities(Map<String, dynamic> data) {
    final playurl = _playurl(data);
    final names = _qnNames(playurl);
    final codes = <int>{};
    for (final entry in _codecs(playurl)) {
      for (final raw in _list(entry.codec['accept_qn'])) {
        final qn = jsonInt(raw);
        if (qn != null && qn > 0) codes.add(qn);
      }
      final current = jsonInt(entry.codec['current_qn']);
      if (current != null && current > 0) codes.add(current);
    }
    return [for (final qn in codes.toList()..sort((a, b) => b.compareTo(a))) _quality(qn, names)];
  }

  /// §5.2 / §5.3 / §6.2 lines for one play response requested at
  /// [requested] (null: `qn=0`, the server's default).
  ///
  /// Candidates are sorted by the spec: `current_qn` equal to the request
  /// first, then confirmed before unconfirmed, `http_stream` before
  /// `http_hls`, `flv` < `ts` < `fmp4`, `avc` first, `mcdn` hosts last, URL.
  /// The first candidate fixes the delivered qn and the codec; only lines with
  /// both are kept, so one set never mixes AVC and HEVC (legacy did when the
  /// request asked for `codec=0,1`). Line id is host + protocol + format +
  /// codec. Headers are the media headers for the long [roomId] with
  /// [cookie]; the lease comes from `expires` (see [lease]).
  static StreamSet streams(
    Map<String, dynamic> data, {
    required String roomId,
    required DateTime issuedAt,
    Quality? requested,
    String? cookie,
  }) {
    final playurl = _playurl(data);
    final names = _qnNames(playurl);
    final offered = qualities(data);
    final requestedQn = requested == null ? null : int.tryParse(requested.id);
    final candidates = <_Candidate>[];
    for (final entry in _codecs(playurl)) {
      final type = switch (entry.format) {
        'flv' => StreamFormat.flv,
        'ts' || 'fmp4' => StreamFormat.hls,
        _ => null,
      };
      final base = entry.codec['base_url'];
      if (type == null || base is! String || base.isEmpty) continue;
      final current = jsonInt(entry.codec['current_qn']);
      final codec = jsonString(entry.codec['codec_name'])?.toLowerCase();
      for (final info in _list(entry.codec['url_info'])) {
        if (info is! Map<String, dynamic>) continue;
        final host = info['host'];
        final extra = info['extra'];
        final url = Uri.tryParse('${host is String ? host.trim() : ''}$base${extra is String ? extra.trim() : ''}');
        if (url == null || (!url.isScheme('http') && !url.isScheme('https')) || url.host.isEmpty) continue;
        candidates.add((
          url: url,
          qn: current != null && current > 0 ? current : null,
          protocol: entry.protocol,
          format: entry.format,
          codec: codec,
          type: type,
        ));
      }
    }
    if (candidates.isEmpty) throw const StreamUnavailable(_site, 'getRoomPlayInfo: no playable line');
    candidates.sort((a, b) => _compareCandidates(a, b, requestedQn));
    final first = candidates.first;
    final confirmed = first.qn == null
        ? null
        : offered.firstWhere((q) => q.id == '${first.qn}', orElse: () => _quality(first.qn!, names));
    final selected =
        requested ?? confirmed ?? (offered.isNotEmpty ? offered.first : const Quality(id: '0', label: '默认', rank: 0));
    final headers = mediaHeaders(roomId, cookie: cookie);
    final seen = <String>{};
    return StreamSet(
      qualities: offered,
      selected: selected,
      lines: [
        for (final candidate in candidates)
          if (candidate.qn == first.qn && candidate.codec == first.codec && seen.add(candidate.url.toString()))
            StreamLine(
              url: candidate.url,
              format: candidate.type,
              lineId: '${candidate.url.host}|${candidate.protocol}|${candidate.format}|${candidate.codec ?? ''}',
              requested: selected,
              confirmed: confirmed,
              headers: headers,
              codec: candidate.codec,
              lease: lease(candidate.url, issuedAt),
            ),
      ],
    );
  }

  /// §6.3 media request headers for the long [roomId]: UA, Origin, Referer
  /// and the cookie (login cookie, or the guest buvid cookie). Never
  /// `authority` or browser navigation headers (REG-BILIBILI-016).
  static Map<String, String> mediaHeaders(String roomId, {String? cookie}) => {
    'user-agent': userAgent,
    'origin': 'https://live.bilibili.com',
    'referer': 'https://live.bilibili.com/$roomId',
    if (cookie != null && cookie.trim().isNotEmpty) 'cookie': cookie.trim(),
  };

  /// §6.5 lease of a media URL received at [issuedAt]. The recording shows
  /// `expires=` (Unix seconds, issue time + 3600 s) in every `extra`;
  /// `stream_ttl` is always 0 and is ignored. Renewal is scheduled
  /// [leaseLead] (at most a quarter of the lifetime) before expiry, and
  /// expiry is taken not to cut an established connection: legacy treated
  /// lines as long-lived and the spec's `cutsConnection` is unconfirmed, so
  /// the player only prefetches. No `expires`, or one already past, is no
  /// lease.
  static Lease? lease(Uri url, DateTime issuedAt) {
    final match = RegExp(r'(?:^|&)expires=(\d+)(?:&|$)').firstMatch(url.query);
    final expires = match == null ? null : int.tryParse(match.group(1)!);
    if (expires == null || expires <= 0) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final quarter = lifetime ~/ 4;
    return Lease(
      refreshAt: expiresAt.subtract(quarter < leaseLead ? quarter : leaseLead),
      expiresAt: expiresAt,
      cutsConnection: false,
    );
  }

  static const _qnLabels = {30000: '杜比', 20000: '4K', 10000: '原画', 400: '蓝光', 250: '超清', 150: '高清', 80: '流畅'};

  static Quality _quality(int qn, Map<int, String> names) =>
      Quality(id: '$qn', label: _qnLabels[qn] ?? names[qn] ?? '清晰度 $qn', rank: qn);

  static Map<int, String> _qnNames(Map<String, dynamic> playurl) => {
    for (final raw in _list(playurl['g_qn_desc']))
      if (raw is Map<String, dynamic> && jsonInt(raw['qn']) != null && jsonString(raw['desc']) != null)
        jsonInt(raw['qn'])!: jsonString(raw['desc'])!,
  };

  static Map<String, dynamic> _playurl(Map<String, dynamic> data) {
    final playurl = _object(_object(data['playurl_info'])?['playurl']);
    if (playurl == null) throw const ApiChanged(_site, 'getRoomPlayInfo: playurl_info.playurl missing');
    return playurl;
  }

  static Iterable<({String protocol, String format, Map<String, dynamic> codec})> _codecs(
    Map<String, dynamic> playurl,
  ) sync* {
    for (final stream in _list(playurl['stream'])) {
      if (stream is! Map<String, dynamic>) continue;
      final protocol = jsonString(stream['protocol_name']) ?? '';
      for (final format in _list(stream['format'])) {
        if (format is! Map<String, dynamic>) continue;
        final name = jsonString(format['format_name']) ?? '';
        for (final codec in _list(format['codec'])) {
          if (codec is Map<String, dynamic>) yield (protocol: protocol, format: name, codec: codec);
        }
      }
    }
  }

  static int _compareCandidates(_Candidate a, _Candidate b, int? requestedQn) {
    final byRequest = (requestedQn != null && a.qn == requestedQn ? 0 : 1).compareTo(
      requestedQn != null && b.qn == requestedQn ? 0 : 1,
    );
    if (byRequest != 0) return byRequest;
    final byConfirmed = (a.qn != null ? 0 : 1).compareTo(b.qn != null ? 0 : 1);
    if (byConfirmed != 0) return byConfirmed;
    final byProtocol = _protocolRank(a.protocol).compareTo(_protocolRank(b.protocol));
    if (byProtocol != 0) return byProtocol;
    final byFormat = _formatRank(a.format).compareTo(_formatRank(b.format));
    if (byFormat != 0) return byFormat;
    final byCodec = _codecRank(a.codec).compareTo(_codecRank(b.codec));
    if (byCodec != 0) return byCodec;
    final byEdge = (a.url.host.contains('mcdn') ? 1 : 0).compareTo(b.url.host.contains('mcdn') ? 1 : 0);
    if (byEdge != 0) return byEdge;
    return a.url.toString().compareTo(b.url.toString());
  }

  static int _protocolRank(String protocol) => switch (protocol) {
    'http_stream' => 0,
    'http_hls' => 1,
    _ => 2,
  };

  static int _formatRank(String format) => switch (format) {
    'flv' => 0,
    'ts' => 1,
    'fmp4' => 2,
    _ => 3,
  };

  static int _codecRank(String? codec) => switch (codec) {
    'avc' => 0,
    'hevc' => 1,
    _ => 2,
  };

  /// A card from `second/getList`, `getListByAreaID` or `getMoreRecList`.
  static RoomCard? _listCard(Map<String, dynamic> item) {
    final id = _roomId(item['roomid'] ?? item['room_id']);
    if (id == null) return null;
    return RoomCard(
      ref: RoomRef(_site, id),
      title: decodeHtmlEntities(jsonString(item['title']) ?? ''),
      anchorName: decodeHtmlEntities(jsonString(item['uname']) ?? ''),
      state: LiveState.live,
      cover: _image(item['cover'], '@400w.jpg') ?? _image(item['user_cover'], '@400w.jpg'),
      area: jsonString(item['area_v2_name']) ?? jsonString(item['area_name']) ?? jsonString(item['areaName']),
      audience: _audience(item['online'], item['watched_show'], LiveState.live),
      avatar: _image(item['face']),
    );
  }

  static RoomCard? _searchRoom(Map<String, dynamic> item) {
    final id = _roomId(item['roomid']);
    if (id == null) return null;
    final state = _searchState(item['live_status']);
    return RoomCard(
      ref: RoomRef(_site, id),
      title: _highlighted(item['title']),
      anchorName: _highlighted(item['uname']),
      state: state,
      // DIAGNOSIS: `cover` is a keyframe screenshot; the room cover is `user_cover`.
      cover: _image(item['user_cover'], '@400w.jpg') ?? _image(item['cover'], '@400w.jpg'),
      area: jsonString(item['cate_name']),
      audience: _audience(item['online'], item['watched_show'], state),
      liveSince: state == LiveState.live ? _beijingTime(item['live_time']) : null,
    );
  }

  static RoomCard? _searchUser(Map<String, dynamic> item) {
    final id = _roomId(item['roomid']);
    if (id == null) return null;
    return RoomCard(
      ref: RoomRef(_site, id),
      title: '',
      anchorName: _highlighted(item['uname']),
      state: _searchState(item['live_status']),
      area: jsonString(item['cate_name']),
    );
  }

  /// Search reports 1 live and 2 replay (v4 §4.3 rule); anything else is offline.
  static LiveState _searchState(Object? value) => switch (jsonInt(value)) {
    1 => LiveState.live,
    2 => LiveState.replay,
    _ => LiveState.offline,
  };

  /// `online` is popularity (§4.4). `watched_show` with `switch: true` is the
  /// broadcast's "N人看过" count, i.e. cumulative viewers; with `switch:
  /// false` it repeats `online` ("N人气") and adds nothing. An offline room's
  /// "看过" count belongs to no broadcast and is dropped.
  static Audience _audience(Object? online, Object? watched, LiveState state) {
    final show = _object(watched);
    final seen = show != null && show['switch'] == true && state != LiveState.offline ? _count(show['num']) : null;
    return Audience(popularity: _count(online), cumulative: seen);
  }

  static int? _count(Object? value) {
    final count = jsonInt(value);
    return count != null && count >= 0 ? count : null;
  }

  /// Sorts by popularity, highest first, rooms without one last; ties by
  /// room identity, then platform order (§2.2, §2.3).
  static List<RoomCard> _byPopularity(List<RoomCard> rooms) {
    final indexed = rooms.indexed.toList()
      ..sort((a, b) {
        final left = a.$2.audience.popularity;
        final right = b.$2.audience.popularity;
        if ((left == null) != (right == null)) return left == null ? 1 : -1;
        final byValue = (right ?? 0).compareTo(left ?? 0);
        if (byValue != 0) return byValue;
        final byRef = a.$2.ref.key.compareTo(b.$2.ref.key);
        return byRef != 0 ? byRef : a.$1.compareTo(b.$1);
      });
    return [for (final (_, room) in indexed) room];
  }

  static final _emTag = RegExp(r'</?em\b[^>]*>', caseSensitive: false);

  /// Search text without the `<em class="keyword">` highlight, entities decoded.
  static String _highlighted(Object? value) => decodeHtmlEntities((jsonString(value) ?? '').replaceAll(_emTag, ''));

  /// The recording shows HTML in `description` (`<p>…</p>`): block ends and
  /// `<br>` become line breaks, other tags are dropped, entities decoded.
  static String? _richText(Object? value) {
    final text = jsonString(value);
    if (text == null) return null;
    final lines = decodeHtmlEntities(
      text
          .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>', caseSensitive: false), '\n')
          .replaceAll(RegExp('<[^>]*>'), ''),
    ).split('\n').map((line) => line.trim());
    final plain = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return plain.isEmpty ? null : plain;
  }

  /// `live_time` in search results is Beijing time, `yyyy-MM-dd HH:mm:ss`;
  /// `0000-00-00 00:00:00` means none.
  static DateTime? _beijingTime(Object? value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$').firstMatch(jsonString(value) ?? '');
    if (match == null || int.parse(match.group(1)!) < 2000) return null;
    return DateTime.tryParse('${match.group(0)!.replaceFirst(' ', 'T')}+08:00');
  }
}

typedef _Candidate = ({Uri url, int? qn, String protocol, String format, String? codec, StreamFormat type});

/// Bilibili room ids are positive decimal integers.
String? _roomId(Object? value) {
  final id = jsonInt(value);
  return id != null && id > 0 ? '$id' : null;
}

/// An image URL: protocol-relative `//…` becomes https (REG-BILIBILI-017);
/// [suffix] is the size hint (`@400w.jpg`).
Uri? _image(Object? value, [String suffix = '']) {
  final text = jsonString(value);
  if (text == null) return null;
  return jsonUrl('${text.startsWith('//') ? 'https:$text' : text}$suffix');
}

Map<String, dynamic>? _object(Object? value) => value is Map<String, dynamic> ? value : null;

List<Object?> _list(Object? value) => value is List ? value.cast<Object?>() : const [];

/// A short single-line excerpt of [body] for `ApiChanged` details.
String _snippet(String body) {
  final text = body.trim().replaceAll(RegExp(r'\s+'), ' ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

/// The JSON envelope `{code, message, data}` of every Bilibili API, checked
/// by §9: HTTP 412 or code -412 → [RateLimited]; HTTP 5xx →
/// [NetworkFailure]; -352 → [RiskControl]; -101 → [NeedsLogin]; codes in
/// [notFound] → [NotFound]; any other non-zero code, a non-2xx status or a
/// body that is not a JSON object → [ApiChanged].
Map<String, dynamic> _checked(String body, {required int status, required String what, Set<int> notFound = const {}}) {
  if (status == 412) throw RateLimited(_site, detail: '$what: HTTP 412');
  if (status >= 500) throw NetworkFailure(_site, '$what: HTTP $status');
  final ok = status >= 200 && status < 300;
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    decoded = null;
  }
  if (decoded is! Map<String, dynamic>) {
    throw ApiChanged(_site, '$what: ${ok ? 'not a JSON object' : 'HTTP $status'} (${_snippet(body)})');
  }
  final code = jsonInt(decoded['code']);
  if (code == 0 && ok) return decoded;
  final detail = '$what: code $code ${jsonString(decoded['message']) ?? jsonString(decoded['msg']) ?? ''}'.trim();
  switch (code) {
    case -352:
      throw RiskControl(_site, detail: detail);
    case -412:
      throw RateLimited(_site, detail: detail);
    case -101:
      throw NeedsLogin(_site, detail);
    case final int value when notFound.contains(value):
      throw NotFound(_site, detail);
  }
  throw ApiChanged(_site, ok ? detail : 'HTTP $status, $detail');
}
