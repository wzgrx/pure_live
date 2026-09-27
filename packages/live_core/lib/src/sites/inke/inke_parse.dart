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

const _site = 'inke';

/// Pure parsing of Inke responses (spec/sites/inke.md).
abstract final class InkeParse {
  /// §1 a uid: 1–18 digits without a leading zero.
  static final RegExp uidPattern = RegExp(r'^[1-9][0-9]{0,17}$');

  /// §4 the web API's "no current live" code (also for unknown uids).
  static const noLiveCode = 1099999920;

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

  static List<dynamic> _list(Object? value, String what) {
    if (value is List) return value;
    throw ApiChanged(_site, '$what: expected a list');
  }

  static void _status(int status, String what) {
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what HTTP $status');
    if (status == 404) throw NotFound(_site, '$what HTTP 404');
    if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status');
    if (status < 200 || status >= 300) throw ApiChanged(_site, '$what HTTP $status');
  }

  /// §2 the `data` of a web API (`webapi.busi.inke.cn/web/…`) response;
  /// null for [noLiveCode].
  static Map<String, dynamic>? webData(String body, {required String what, int status = 200}) {
    _status(status, what);
    final root = _map(_json(body, what), what);
    final code = jsonInt(root['error_code']);
    if (code == noLiveCode) return null;
    if (code != 0) throw ApiChanged(_site, '$what error_code $code: ${jsonString(root['message']) ?? ''}');
    return _map(root['data'], '$what.data');
  }

  /// §2 an app API (`service.inke.cn/api/…`) response.
  static Map<String, dynamic> serviceData(String body, {required String what, int status = 200}) {
    _status(status, what);
    final root = _map(_json(body, what), what);
    final code = jsonInt(root['dm_error']);
    if (code != 0) throw ApiChanged(_site, '$what dm_error $code: ${jsonString(root['error_msg']) ?? ''}');
    return root;
  }

  /// §2.1 `Live_channel_pc` groups as areas of one category.
  static List<Category> categories(String body, {int status = 200}) {
    final data = webData(body, what: 'Live_channel_pc', status: status);
    if (data == null) throw const ApiChanged(_site, 'Live_channel_pc: no data');
    return [
      Category(
        id: 'channel',
        name: '频道',
        areas: [
          for (final group in _list(data['list'], 'Live_channel_pc.list'))
            if (group is Map && jsonString(group['tab_key']) != null && jsonString(group['channel_name']) != null)
              Area(id: jsonString(group['tab_key'])!, name: jsonString(group['channel_name'])!, categoryId: 'channel'),
        ],
      ),
    ];
  }

  /// §2.2 the rooms of channel [tabKey] (one page); an unknown channel is
  /// NotFound.
  static Page<RoomCard> channelPage(String body, {required String tabKey, int status = 200}) {
    final data = webData(body, what: 'Live_channel_pc', status: status);
    final groups = data == null ? const <Object?>[] : _list(data['list'], 'Live_channel_pc.list');
    final group = groups.whereType<Map<dynamic, dynamic>>().where((g) => g['tab_key'] == tabKey).firstOrNull;
    if (group == null) throw NotFound(_site, 'channel $tabKey');
    return Page(_showcaseCards(_list(group['list'], 'channel.list')));
  }

  /// §2.2 `Live_top_pc` (one page).
  static Page<RoomCard> topPage(String body, {int status = 200}) {
    final data = webData(body, what: 'Live_top_pc', status: status);
    return Page(data == null ? const [] : _showcaseCards(_list(data['list'], 'Live_top_pc.list')));
  }

  /// §2.2 showcase rows: uid, nick, portrait; all live, no title (the nick
  /// stands in).
  static List<RoomCard> _showcaseCards(List<dynamic> rows) {
    final seen = <String>{};
    return [
      for (final row in rows)
        if (row is Map && uidPattern.hasMatch('${row['uid']}') && seen.add('${row['uid']}'))
          RoomCard(
            ref: RoomRef(_site, '${row['uid']}'),
            title: jsonString(row['nick']) ?? '',
            anchorName: jsonString(row['nick']) ?? '',
            state: LiveState.live,
            cover: jsonUrl(row['portrait']),
            avatar: jsonUrl(row['portrait']),
          ),
    ];
  }

  /// §2.3 audience of an app live: `numbers.real` is the number the app
  /// shows as "N人在看"; `online_users` is a larger display figure (heat).
  static Audience audience(Map<dynamic, dynamic> live) {
    final numbers = live['numbers'];
    final real = numbers is Map ? jsonInt(numbers['real']) : null;
    final shown = jsonInt(live['online_users']);
    return Audience(
      online: real != null && real >= 0 ? real : null,
      popularity: shown != null && shown >= 0 ? shown : null,
    );
  }

  /// §2.3 `api/live/simpleall` lives (one page).
  static Page<RoomCard> simpleallPage(String body, {int status = 200}) {
    final root = serviceData(body, what: 'simpleall', status: status);
    final seen = <String>{};
    final rooms = <RoomCard>[];
    for (final live in _list(root['lives'] ?? const [], 'simpleall.lives')) {
      if (live is! Map) continue;
      final creator = live['creator'];
      final uid = creator is Map ? '${creator['id']}' : '';
      if (!uidPattern.hasMatch(uid) || !seen.add(uid)) continue;
      final nick = creator is Map ? jsonString(creator['nick']) ?? '' : '';
      final start = jsonInt(live['start_time']);
      rooms.add(
        RoomCard(
          ref: RoomRef(_site, uid),
          title: decodeHtmlEntities(jsonString(live['name']) ?? nick),
          anchorName: nick,
          state: LiveState.live,
          cover: jsonUrl(live['cover']) ?? (creator is Map ? jsonUrl(creator['portrait']) : null),
          audience: audience(live),
          liveSince: start != null && start > 0 ? DateTime.fromMillisecondsSinceEpoch(start * 1000, isUtc: true) : null,
          avatar: creator is Map ? jsonUrl(creator['portrait']) : null,
        ),
      );
    }
    return Page(rooms);
  }

  /// §4 the current live of `api/live/now_publish?id=<uid>`, or null.
  static Map<String, dynamic>? publishedLive(String body, {required String uid, int status = 200}) {
    final root = serviceData(body, what: 'now_publish', status: status);
    final live = root['live'];
    if (live == null) return null;
    final map = _map(live, 'now_publish.live');
    if ('${map['creator']}' != uid) throw ApiChanged(_site, 'now_publish: live of ${map['creator']} for $uid');
    return map;
  }

  /// §4 the room from `live_share_pc` (the anchor) and `now_publish` (the
  /// live); without a current live both answer "none" and the room is
  /// offline with only its uid.
  static RoomDetail detail({
    required String uid,
    required String shareBody,
    required String publishBody,
    int shareStatus = 200,
    int publishStatus = 200,
  }) {
    final share = webData(shareBody, what: 'live_share_pc', status: shareStatus);
    final live = publishedLive(publishBody, uid: uid, status: publishStatus);
    final media = share?['media_info'];
    final nick = media is Map ? jsonString(media['nick']) ?? '' : '';
    final avatar = media is Map ? jsonUrl(media['portrait']) : null;
    final liveId = jsonString(live?['id']) ?? jsonString(share?['liveid']);
    final isLive = live != null && jsonInt(live['status']) == 1;
    if (share != null && '${share['live_uid']}' != uid) throw const ApiChanged(_site, 'live_share_pc: another anchor');
    final start = live == null ? null : jsonInt(live['start_time']);
    return RoomDetail(
      card: RoomCard(
        ref: RoomRef(_site, uid),
        title: decodeHtmlEntities(jsonString(live?['name']) ?? jsonString(share?['live_name']) ?? nick),
        anchorName: nick,
        state: isLive ? LiveState.live : LiveState.offline,
        cover: jsonUrl(live?['cover']) ?? avatar,
        audience: isLive ? audience(live) : Audience.none,
        liveSince: isLive && start != null && start > 0
            ? DateTime.fromMillisecondsSinceEpoch(start * 1000, isUtc: true)
            : null,
        avatar: avatar,
      ),
      link: Uri.parse(
        'https://www.inke.cn/liveroom/index.html?uid=$uid${isLive && liveId != null ? '&id=$liveId' : ''}',
      ),
      avatar: avatar,
      introduction: media is Map ? jsonString(media['description']) : null,
    );
  }

  /// §5 the Wangsu pull URL `https://live-pull-ws.ikstatic.cn/live/<id>_t.flv`
  /// (H.264); anything else is skipped.
  static Uri? mediaUrl(Object? value, {required String liveId}) {
    final url = jsonUrl(value);
    if (url == null ||
        url.host != 'live-pull-ws.ikstatic.cn' ||
        url.path != '/live/${liveId}_t.flv' ||
        (url.queryParameters['wsSecret'] ?? '').isEmpty) {
      return null;
    }
    return url.replace(scheme: 'https');
  }

  /// §6.2 lease from `wsABStime` (hex Unix seconds): refresh min(10 min, a
  /// quarter of the lifetime) before; expiry does not cut an open FLV
  /// connection (Wangsu checks at connect time) [待确认].
  static Lease? lease(Uri url, {required DateTime issuedAt}) {
    final expires = int.tryParse(url.queryParameters['wsABStime'] ?? '', radix: 16);
    if (expires == null || expires <= 0) return null;
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true);
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero) return null;
    final lead = Duration(
      microseconds: math.min(const Duration(minutes: 10).inMicroseconds, lifetime.inMicroseconds ~/ 4),
    );
    return Lease(refreshAt: expiresAt.subtract(lead), expiresAt: expiresAt, cutsConnection: false);
  }

  /// §5/§6 the stream of `now_publish`: the H.264 Wangsu line only. The
  /// Zego line (`stream_multi_addr`, `codecInfo=8192`) is FLV with codec id
  /// 12 (HEVC), which the player cannot demux yet (spec §6.4).
  static StreamSet streams(
    String publishBody, {
    required String uid,
    required DateTime issuedAt,
    required Map<String, String> headers,
    int status = 200,
  }) {
    final live = publishedLive(publishBody, uid: uid, status: status);
    if (live == null || jsonInt(live['status']) != 1) throw const StreamUnavailable(_site, 'no current live');
    final liveId = jsonString(live['id']) ?? '';
    final url = mediaUrl(live['stream_addr'], liveId: liveId);
    if (url == null) throw const StreamUnavailable(_site, 'no H.264 pull URL');
    return StreamSet(
      qualities: const [original],
      selected: original,
      lines: [
        StreamLine(
          url: url,
          format: StreamFormat.flv,
          lineId: 'ws',
          requested: original,
          confirmed: original,
          headers: headers,
          codec: 'avc',
          lease: lease(url, issuedAt: issuedAt),
        ),
      ],
    );
  }

  /// §1 the uid of an input: digits, or an Inke room page or share link
  /// (`uid` query parameter), also inside share text; null otherwise.
  static String? uidOf(String input) {
    final text = input.trim();
    if (uidPattern.hasMatch(text)) return text;
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null || (url.scheme != 'http' && url.scheme != 'https')) return null;
    final host = url.host.toLowerCase();
    final web = const {'inke.cn', 'www.inke.cn', 'inke.com', 'www.inke.com'}.contains(host);
    final share = RegExp(r'^mlive\d*\.inke\.cn$').hasMatch(host);
    if (!(web && url.path == '/liveroom/index.html') && !(share && url.path.startsWith('/app/'))) return null;
    final uid = url.queryParameters['uid'] ?? '';
    return uidPattern.hasMatch(uid) ? uid : null;
  }
}
