import 'dart:convert';
import 'dart:math' as math;

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';
import 'package:meta/meta.dart';

const _site = 'kilakila';

/// An anchor's public profile (spec §4): the uid is the room identity; the
/// current broadcast, when there is one, is in [live].
@immutable
final class KilakilaAnchor {
  /// Creates a profile.
  const new({required this.uid, required this.nickname, this.avatar, this.introduction, this.live});

  /// Anchor uid.
  final String uid;

  /// Display name.
  final String nickname;

  /// Avatar.
  final Uri? avatar;

  /// Introduction.
  final String? introduction;

  /// The current broadcast's card (`liveCard`), or null when none.
  final Map<String, dynamic>? live;
}

/// Pure parsing of KilaKila responses (spec/sites/kilakila.md).
abstract final class KilakilaParse {
  /// §1 ids: uids and broadcast ids are 1–32 digits without a leading zero.
  static final RegExp idPattern = RegExp(r'^[1-9][0-9]{0,31}$');

  /// §2.1 the two timelines.
  static const timelines = {'0': '热门', '107': '萌星'};

  /// §2.2 the page cap: the timelines cycle instead of ending.
  static const maxPages = 100;

  /// §5 the single quality.
  static const original = Quality(id: 'origin', label: '原画', rank: 1);

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

  static void _status(int status, String what) {
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what HTTP $status');
    if (status == 404) throw NotFound(_site, '$what HTTP 404');
    if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, '$what HTTP $status');
  }

  /// §9 the `{h, b}` envelope: `h.code` 200 with `h.success`; 5201 is a
  /// room that does not exist.
  static Map<String, dynamic>? _envelope(Map<String, dynamic> root, String what) {
    final header = _map(root['h'], '$what.h');
    final code = jsonInt(header['code']);
    if (code == 5201) throw NotFound(_site, '$what: ${jsonString(header['msg']) ?? code}');
    if (code != 200 || header['success'] != true) {
      throw ApiChanged(_site, '$what: h.code $code ${jsonString(header['msg']) ?? ''}');
    }
    final body = root['b'];
    return body is Map<String, dynamic> ? body : null;
  }

  /// §2.2 a `pcLive/timeline` page of timeline [type] (`0` 热门 uses
  /// `dataType` 8, `107` 萌星 uses 2). Ends at `isLastPage`, an empty
  /// page, or [maxPages].
  static Page<RoomCard> timelinePage(String body, {required int page, required String type, int status = 200}) {
    _status(status, 'timeline');
    final root = _map(_json(body, 'timeline'), 'timeline');
    if (jsonInt(root['code']) != 200) throw ApiChanged(_site, 'timeline code ${root['code']}');
    final wrapped = _map(_map(root['data'], 'timeline.data')['body'], 'timeline.data.body');
    final data = _envelope(wrapped, 'timeline') ?? const <String, dynamic>{};
    final rows = data['data'] is List ? data['data'] as List : const <Object?>[];
    final wanted = type == '107' ? 2 : 8;
    final seen = <String>{};
    final rooms = <RoomCard>[
      for (final row in rows)
        if (row is Map && jsonInt(row['dataType']) == wanted && row['roomResq'] is Map)
          if (_card(row['roomResq'] as Map, row['userResp']) case final card? when seen.add(card.ref.roomId)) card,
    ];
    final last = data['isLastPage'] == true || rows.isEmpty || page >= maxPages;
    return Page(rooms, next: last ? null : PageCursor('${page + 1}'));
  }

  /// §4 `status` of a broadcast: 4 live, 10 ended (replay); others are an
  /// unknown shape.
  static LiveState state(Object? value) => switch (jsonInt(value)) {
    4 => LiveState.live,
    10 => LiveState.replay,
    final other => throw ApiChanged(_site, 'broadcast status $other'),
  };

  static Uri? _cover(Map<dynamic, dynamic> room) =>
      jsonUrl(room['backPic']) ?? jsonUrl(room['defaultBackgroundPicUrl']);

  static Audience _audience(Map<dynamic, dynamic> room) {
    final online = jsonInt(room['onlineNumber']);
    final watch = jsonInt(room['watchNumber']);
    return Audience(
      online: online != null && online > 0 ? online : null,
      cumulative: watch != null && watch >= 0 ? watch : null,
    );
  }

  /// A live card from a timeline row; rows that are not live are skipped.
  static RoomCard? _card(Map<dynamic, dynamic> room, Object? user) {
    final uid = '${room['uid'] ?? ''}';
    if (!idPattern.hasMatch(uid) || jsonInt(room['status']) != 4) return null;
    final owner = user is Map ? user : const <String, Object?>{};
    return RoomCard(
      ref: RoomRef(_site, uid),
      title: decodeHtmlEntities(jsonString(room['title']) ?? ''),
      anchorName: jsonString(owner['nickname']) ?? '',
      state: LiveState.live,
      cover: _cover(room),
      audience: _audience(room),
      avatar: jsonUrl(owner['headPortraitUrl']),
    );
  }

  /// §4 `Tg/personalH5?uid=`: code 1013 is an unknown account.
  static KilakilaAnchor anchor(String body, {required String uid, int status = 200}) {
    _status(status, 'personalH5');
    final root = _map(_json(body, 'personalH5'), 'personalH5');
    final code = jsonInt(root['code']);
    if (code == 1013) throw NotFound(_site, 'personalH5: ${jsonString(root['msg']) ?? code}');
    if (code != 200) throw ApiChanged(_site, 'personalH5 code $code');
    final data = _map(root['data'], 'personalH5.data');
    final user = _map(data['userResp'], 'personalH5.userResp');
    final card = data['liveCard'];
    Map<String, dynamic>? live;
    // §4 a card of routing defaults only (`roomSourceType`,
    // `recommendSource`) means no current broadcast.
    if (card is Map<String, dynamic> && card.containsKey('roomIdStr')) {
      if ('${card['uid']}' != uid) throw const ApiChanged(_site, 'personalH5: liveCard of another anchor');
      live = card;
    } else if (card is! Map) {
      throw const ApiChanged(_site, 'personalH5: no liveCard');
    }
    return KilakilaAnchor(
      uid: uid,
      nickname: jsonString(user['nickname']) ?? '',
      avatar: jsonUrl(user['headPortraitUrl']),
      introduction: jsonString(user['introduction']),
      live: live,
    );
  }

  /// §4 the room of an anchor profile.
  static RoomDetail detail(KilakilaAnchor anchor) {
    final live = anchor.live;
    final link = Uri.parse('https://live.hongrenshuo.com.cn/index/roomuser/uid/${anchor.uid}');
    if (live == null) {
      return RoomDetail(
        card: RoomCard(
          ref: RoomRef(_site, anchor.uid),
          title: anchor.nickname,
          anchorName: anchor.nickname,
          state: LiveState.offline,
          cover: anchor.avatar,
          avatar: anchor.avatar,
        ),
        link: link,
        avatar: anchor.avatar,
        introduction: anchor.introduction,
      );
    }
    final state = KilakilaParse.state(live['status']);
    final started = jsonInt(live['actualTime']) ?? jsonInt(live['liveStartTime']);
    final roomId = jsonString(live['roomIdStr']);
    if (roomId == null || !idPattern.hasMatch(roomId)) throw const ApiChanged(_site, 'liveCard.roomIdStr');
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, anchor.uid),
        title: decodeHtmlEntities(jsonString(live['title']) ?? anchor.nickname),
        anchorName: anchor.nickname,
        state: state,
        cover: _cover(live) ?? anchor.avatar,
        audience: _audience(live),
        liveSince: state == LiveState.live && started != null && started > 0
            ? DateTime.fromMillisecondsSinceEpoch(started, isUtc: true)
            : null,
        avatar: anchor.avatar,
      ),
      link: link,
      avatar: anchor.avatar,
      introduction: anchor.introduction,
      danmakuKeys: {'roomId': roomId},
    );
  }

  /// §1/§4 `LiveRoom/getRoomInfo`: the broadcast object `b`.
  static Map<String, dynamic> roomInfo(String body, {int status = 200}) {
    _status(status, 'getRoomInfo');
    final root = _map(_json(body, 'getRoomInfo'), 'getRoomInfo');
    final data = _envelope(root, 'getRoomInfo');
    if (data == null || jsonString(data['roomIdStr']) == null) throw const ApiChanged(_site, 'getRoomInfo: no room');
    return data;
  }

  /// §1 the anchor uid of a broadcast.
  static String anchorOf(Map<String, dynamic> room) {
    final uid = '${room['uid'] ?? ''}';
    if (!idPattern.hasMatch(uid)) throw const ApiChanged(_site, 'getRoomInfo: no uid');
    return uid;
  }

  /// §5 a pull URL: `https://pull.live.hongrenshuo.com.cn/hrs/<room>.<ext>`
  /// with an `auth_key`; anything else is skipped.
  static Uri? mediaUrl(Object? value, {required String roomId, required StreamFormat format}) {
    final url = jsonUrl(value);
    final extension = format == StreamFormat.flv ? 'flv' : 'm3u8';
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'pull.live.hongrenshuo.com.cn' ||
        url.path != '/hrs/$roomId.$extension' ||
        (url.queryParameters['auth_key'] ?? '').isEmpty) {
      return null;
    }
    return url;
  }

  /// §6.2 lease from the expiry that leads `auth_key`
  /// (`<Unix s>-<rand>-<uid>-<md5>`): refresh min(10 min, a quarter of the
  /// lifetime) before.
  static Lease? lease(Uri url, {required DateTime issuedAt, required bool cutsConnection}) {
    final expires = int.tryParse((url.queryParameters['auth_key'] ?? '').split('-').first);
    if (expires == null || expires <= 0) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final lead = Duration(
      microseconds: math.min(const Duration(minutes: 10).inMicroseconds, lifetime.inMicroseconds ~/ 4),
    );
    return Lease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt, cutsConnection: cutsConnection);
  }

  /// §5/§6 the lines of a live broadcast fetched at [issuedAt]: FLV then
  /// HLS under one quality. A paid room needs an account; a broadcast that
  /// is not live has no stream.
  static StreamSet streams(
    Map<String, dynamic> room, {
    required DateTime issuedAt,
    required Map<String, String> headers,
  }) {
    final roomId = jsonString(room['roomIdStr'])!;
    if (state(room['status']) != LiveState.live) throw const StreamUnavailable(_site, 'broadcast is not live');
    if ((jsonInt(room['goldPrice']) ?? 0) != 0) throw const NeedsLogin(_site, 'paid room');
    final lines = <StreamLine>[
      for (final (key, format) in const [('flvPlayUrl', StreamFormat.flv), ('hlsPlayUrl', StreamFormat.hls)])
        if (mediaUrl(room[key], roomId: roomId, format: format) case final url?)
          StreamLine(
            url: url,
            format: format,
            lineId: format.name,
            requested: original,
            confirmed: original,
            headers: headers,
            lease: lease(url, issuedAt: issuedAt, cutsConnection: format == StreamFormat.hls),
          ),
    ];
    if (lines.isEmpty) throw const StreamUnavailable(_site, 'no pull URL');
    return StreamSet(qualities: const [original], selected: original, lines: lines);
  }

  /// §3 the anchors of a search results page (`<a href="/zhubo/<uid>">`
  /// with `.anchorHeaderImg img` and `.anchor-name`), and whether a link to
  /// page [page] + 1 exists.
  static ({List<({String uid, String name, Uri? avatar})> anchors, bool more}) searchPage(
    String html, {
    required int page,
  }) {
    final anchors = <({String uid, String name, Uri? avatar})>[];
    final seen = <String>{};
    final blocks = RegExp(r'<a href="/zhubo/([1-9][0-9]{0,31})">([\s\S]*?)</a>').allMatches(html);
    for (final block in blocks) {
      final uid = block.group(1)!;
      final inner = block.group(2)!;
      final name = RegExp('class="anchor-name">([^<]*)<').firstMatch(inner)?.group(1)?.trim();
      if (name == null || name.isEmpty || !seen.add(uid)) continue;
      final avatar = RegExp('<img src="([^"]+)"').firstMatch(inner)?.group(1);
      anchors.add((uid: uid, name: decodeHtmlEntities(name), avatar: jsonUrl(avatar)));
    }
    final more = RegExp('/aboutus/serach/kw/[^"]*/p/${page + 1}"').hasMatch(html);
    return (anchors: anchors, more: anchors.isNotEmpty && more);
  }
}
