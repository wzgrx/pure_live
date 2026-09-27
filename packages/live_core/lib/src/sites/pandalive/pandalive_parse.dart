import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/hls_playlist.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text.dart';

const _site = 'pandalive';

/// The fields of one `live/play` answer the adapter needs (§6.1).
typedef PandalivePlay = ({String userId, String channel, String chatToken, Uri master});

/// Pure parsing of PandaTV responses (spec/sites/pandalive.md).
abstract final class PandaliveParse {
  /// §1 a broadcaster id; social-login ids carry a suffix (`1506087545@ka`).
  static final RegExp userIdPattern = RegExp(r'^[A-Za-z0-9_]{1,64}(?:@[A-Za-z0-9_]{2,16})?$');

  /// §1 hosts of room links.
  static const hosts = {'pandalive.co.kr', 'www.pandalive.co.kr', 'm.pandalive.co.kr'};

  /// §2 the areas: all public broadcasts by popularity, and new broadcasters.
  static const areas = [
    Area(id: 'hot', name: '全部直播', categoryId: 'live'),
    Area(id: 'newbj', name: '新人主播', categoryId: 'live'),
  ];

  /// §2 the one category.
  static const category = Category(id: 'live', name: 'PandaTV', areas: areas);

  static Object? _json(String body, String what) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
  }

  /// §9 status mapping. PandaTV answers refusals as HTTP 400 with a JSON
  /// body (`result: false`, `message`, `errorData.code`), so a 400 is read
  /// like a 200 and [ok] decides.
  static Map<String, dynamic> root(String body, {required String what, int status = 200}) {
    if (status == 429) throw RateLimited(_site, detail: '$what HTTP 429');
    if (status == 401 || status == 403) throw RiskControl(_site, detail: '$what HTTP $status');
    if (status == 404) throw NotFound(_site, '$what HTTP 404');
    if (status >= 500) throw NetworkFailure(_site, '$what HTTP $status');
    if (status != 400 && (status < 200 || status >= 300)) throw ApiChanged(_site, '$what HTTP $status');
    final data = _json(body, what);
    if (data is! Map<String, dynamic> || data['result'] is! bool) throw ApiChanged(_site, '$what: no result flag');
    return data;
  }

  /// §9 a successful answer, or the typed refusal.
  static Map<String, dynamic> ok(String body, {required String what, int status = 200}) {
    final data = root(body, what: what, status: status);
    if (data['result'] == true) return data;
    throw refusal(data, what: what);
  }

  /// §9 the error of a refused request.
  static SiteError refusal(Map<String, dynamic> data, {required String what}) {
    final message = jsonString(data['message']) ?? '';
    final errorData = data['errorData'];
    final code = errorData is Map ? jsonString(errorData['code']) ?? '' : '';
    return switch (code) {
      'castEnd' => StreamUnavailable(_site, '$what: broadcast ended'),
      'needAdult' || 'needLogin' => NeedsLogin(_site, '$what: $code'),
      'needPassword' || 'password' || 'needPw' => StreamUnavailable(_site, '$what: password-protected'),
      '' when message.contains('유저 정보가 없습니다') => NotFound(_site, '$what: no such broadcaster'),
      '' => ApiChanged(_site, '$what refused: $message'),
      _ => StreamUnavailable(_site, '$what refused: $code'),
    };
  }

  static bool? _flag(Object? value) => switch (value) {
    final bool flag => flag,
    'Y' || 'y' || 1 => true,
    'N' || 'n' || 0 => false,
    _ => null,
  };

  static Uri? _image(Object? value) {
    final url = jsonUrl(value);
    if (url == null || url.scheme != 'https') return null;
    return url.host.toLowerCase().endsWith('pandalive.co.kr') ? url : null;
  }

  /// §2.3 `startTime` is Korean time (UTC+9) without a zone;
  /// `0000-00-00 00:00:00` means none.
  static DateTime? koreanTime(Object? value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$').firstMatch(jsonString(value) ?? '');
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    if (parts[0] < 2000 || parts[1] == 0 || parts[2] == 0) return null;
    return DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]).subtract(const Duration(hours: 9));
  }

  static int? _count(Object? value) {
    final count = jsonInt(value);
    return count != null && count >= 0 ? count : null;
  }

  static String? _userId(Object? value) {
    final id = jsonString(value);
    return id != null && userIdPattern.hasMatch(id) ? id : null;
  }

  /// §1 the page of broadcaster [userId].
  static Uri link(String userId) => Uri.https('www.pandalive.co.kr', '/play/$userId');

  /// §2.3 a card from a broadcast (`live/index` rows, `media` objects).
  static RoomCard? mediaCard(Map<dynamic, dynamic> media, {String? fallbackName, Uri? fallbackAvatar}) {
    final id = _userId(media['userId']);
    if (id == null) return null;
    final live = _flag(media['isLive']) ?? false;
    final name = jsonString(media['userNick']) ?? fallbackName ?? id;
    return RoomCard(
      ref: RoomRef(_site, id),
      title: jsonString(media['title']) ?? name,
      anchorName: name,
      state: live ? LiveState.live : LiveState.offline,
      cover: _image(media['thumbUrl']) ?? _image(media['ivsThumbnail']),
      audience: live ? Audience(online: _count(media['user']), cumulative: _count(media['playCnt'])) : Audience.none,
      liveSince: live ? koreanTime(media['startTime']) : null,
      avatar: _image(media['userImg']) ?? fallbackAvatar,
    );
  }

  static Page<RoomCard> _page(
    Map<String, dynamic> data,
    int offset,
    String what,
    RoomCard? Function(Map<dynamic, dynamic> row) card,
  ) {
    final paging = data['page'];
    final rows = data['list'];
    if (paging is! Map || rows is! List) throw ApiChanged(_site, '$what: no page or list');
    if (jsonInt(paging['offset']) != offset) throw ApiChanged(_site, '$what: page offset ${paging['offset']}');
    final total = jsonInt(paging['total']) ?? 0;
    final seen = <String>{};
    final cards = [
      for (final row in rows)
        if (row is Map && _flag(row['blockService']) != true)
          if (card(row) case final RoomCard c when seen.add(c.ref.roomId.toLowerCase())) c,
    ];
    final next = offset + rows.length;
    return Page(cards, next: rows.isNotEmpty && next < total ? PageCursor('$next') : null);
  }

  /// §2.2 a `live/index` page read at [offset]: live broadcasts.
  static Page<RoomCard> indexPage(String body, {required int offset, int status = 200}) {
    final data = ok(body, what: 'live/index', status: status);
    return _page(data, offset, 'live/index', (row) {
      final card = mediaCard(row);
      return card?.state == LiveState.live ? card : null;
    });
  }

  /// §3 a `live/bj_list` page read at [offset]: broadcasters, live or not.
  static Page<RoomCard> broadcasterPage(String body, {required int offset, int status = 200}) {
    final data = ok(body, what: 'live/bj_list', status: status);
    return _page(data, offset, 'live/bj_list', (row) {
      final id = _userId(row['userId']);
      if (id == null) return null;
      final name = jsonString(row['userNick']) ?? id;
      final avatar = _image(row['thumbUrl']);
      final media = row['media'];
      if (media is Map && _userId(media['userId'])?.toLowerCase() == id.toLowerCase()) {
        return mediaCard(media, fallbackName: name, fallbackAvatar: avatar);
      }
      return RoomCard(ref: RoomRef(_site, id), title: name, anchorName: name, state: LiveState.offline, avatar: avatar);
    });
  }

  /// §4 the room from `member/bj`.
  static RoomDetail detail(String body, {required String userId, int status = 200}) {
    final data = ok(body, what: 'member/bj', status: status);
    final info = data['bjInfo'];
    if (info is! Map) throw const ApiChanged(_site, 'member/bj: no bjInfo');
    final id = _userId(info['id']);
    if (id == null || id.toLowerCase() != userId.toLowerCase()) {
      throw ApiChanged(_site, 'member/bj: bjInfo of ${info['id']} for $userId');
    }
    final index = jsonInt(info['idx']);
    final nick = jsonString(info['nick']) ?? id;
    final avatar = _image(info['thumbUrl']);
    final media = data['media'];
    RoomCard? card;
    if (media is Map) {
      if (_userId(media['userId'])?.toLowerCase() != id.toLowerCase()) {
        throw ApiChanged(_site, 'member/bj: media of ${media['userId']} for $id');
      }
      card = mediaCard(media, fallbackName: nick, fallbackAvatar: avatar);
    }
    final live = card?.state == LiveState.live;
    card = live
        ? card!
        : RoomCard(
            ref: RoomRef(_site, id),
            title: jsonString(info['channelTitle']) ?? nick,
            anchorName: nick,
            state: LiveState.offline,
            cover: _image(info['channelBannerUrl']),
            avatar: avatar,
          );
    return RoomDetail(
      card: card,
      link: link(id),
      avatar: avatar ?? card.avatar,
      introduction: jsonString(info['channelDesc']),
      danmakuKeys: {if (live) 'userId': id, if (live && index != null) 'channel': '$index'},
    );
  }

  /// §6.1 `live/play`: the chat channel and token and the IVS master of a
  /// public live broadcast; refusals (ended, 19+, fans only, password) are
  /// typed errors.
  static PandalivePlay play(String body, {required String userId, int status = 200}) {
    final data = ok(body, what: 'live/play', status: status);
    final media = data['media'];
    if (media is! Map || _userId(media['userId'])?.toLowerCase() != userId.toLowerCase()) {
      throw ApiChanged(_site, 'live/play: media of ${media is Map ? media['userId'] : null} for $userId');
    }
    if (_flag(media['isLive']) != true) throw const StreamUnavailable(_site, 'live/play: not live');
    final lists = data['PlayList'];
    Uri? master;
    if (lists is Map) {
      for (final key in const ['hls3', 'hls2', 'hls']) {
        final entries = lists[key];
        for (final entry in entries is List ? entries : const <Object?>[]) {
          final url = entry is Map ? jsonUrl(entry['url']) : null;
          if (url != null && isMediaHost(url)) {
            master = url;
            break;
          }
        }
        if (master != null) break;
      }
    }
    if (master == null) throw const StreamUnavailable(_site, 'live/play: no HLS master');
    return (
      userId: userId,
      channel: '${jsonInt(data['channel']) ?? jsonString(data['channel']) ?? ''}',
      chatToken: jsonString(data['token']) ?? '',
      master: master,
    );
  }

  /// §6.1 media comes from Amazon IVS over HTTPS.
  static bool isMediaHost(Uri url) => url.scheme == 'https' && url.host.toLowerCase().endsWith('.live-video.net');

  /// §5 one quality per IVS variant (best first); the source rendition
  /// (`VIDEO="chunked"`) is marked 原画. The master itself is single use
  /// (§6.2), so lines are variant playlists.
  static StreamSet streams(String body, {required Uri master, required Map<String, String> headers, String? wanted}) {
    final List<HlsVariant> variants;
    try {
      variants = HlsPlaylist.variants(body, source: master);
    } on FormatException {
      throw const ApiChanged(_site, 'master: not a playlist');
    }
    final offered = <Quality, HlsVariant>{};
    for (final variant in variants) {
      final height = variant.height;
      if (variant.audioOnly || height == null || !isMediaHost(variant.url)) continue;
      final fps = variant.frameRate ?? 0;
      final id = '${height}p${fps >= 50 ? '60' : ''}';
      final source = variant.name == 'chunked';
      final quality = Quality(
        id: id,
        label: source ? '$id 原画' : id,
        rank: height * 100000000 + variant.bandwidth + (source ? 50000000 : 0),
      );
      if (offered.keys.any((q) => q.id == id)) continue;
      offered[quality] = variant;
    }
    if (offered.isEmpty) throw const StreamUnavailable(_site, 'master: no video variant');
    final ordered = offered.keys.toList()..sort((a, b) => b.rank.compareTo(a.rank));
    final selected = ordered.where((q) => q.id == wanted).firstOrNull ?? ordered.first;
    final variant = offered[selected]!;
    return StreamSet(
      qualities: ordered,
      selected: selected,
      lines: [
        StreamLine(
          url: variant.url,
          format: StreamFormat.hls,
          lineId: 'ivs',
          requested: selected,
          confirmed: selected,
          headers: headers,
          codec: variant.videoCodec,
        ),
      ],
    );
  }

  /// §1 the broadcaster a link names (also inside share text); null for
  /// other input.
  static String? userIdOf(String input) {
    final text = input.trim();
    final match = RegExp(r'https?://[^\s，。！？、]+').firstMatch(text);
    final url = Uri.tryParse(match?.group(0) ?? text);
    if (url == null || !url.hasScheme || !hosts.contains(url.host.toLowerCase())) return null;
    final segments = url.pathSegments.where((segment) => segment.isNotEmpty).toList();
    final id = switch (segments) {
      ['play', final id] => id,
      ['live', 'play', final id] => id,
      ['channel', final id, ...] => id,
      _ => null,
    };
    return id != null && userIdPattern.hasMatch(id) ? id : null;
  }
}
