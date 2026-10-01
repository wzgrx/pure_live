import 'dart:convert';

import 'package:live_core/src/audience.dart';
import 'package:live_core/src/hls_master.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'pandalive';

/// A broadcaster from `member/bj`: the channel (`bjInfo`) and, while the
/// platform lists a broadcast, its `media` (3.x read both in `room`).
@immutable
final class PandaLiveMember {
  /// Creates the member.
  new({required this.userId, required this.index, required Map<String, Object?> profile, Map<String, Object?>? media})
    : profile = Map.unmodifiable(profile),
      media = media == null ? null : Map.unmodifiable(media);

  /// The broadcaster id as asked for (3.x kept the requested spelling).
  final String userId;

  /// `bjInfo.idx`: the broadcaster's number (3.x's `userIndex`, the rooms'
  /// `userId` and the chat channel).
  final int index;

  /// `bjInfo`: nick, avatar, channel title, description, banner, fans.
  final Map<String, Object?> profile;

  /// `media`, null while the broadcaster is not live; checked to be this
  /// broadcaster's.
  final Map<String, Object?>? media;
}

/// What `live/play` answered (3.x's second request of room entry).
@immutable
final class PandaLivePlay {
  /// A refusal with `errorData.code` [code] (empty without one).
  const new refused(String this.code) : media = null, master = null, chatChannel = null, chatToken = null;

  /// An accepted answer: its broadcast, the first IVS master of `PlayList`
  /// (null when it has none) and the chat channel and token.
  new accepted({required Map<String, Object?> media, this.master, this.chatChannel, this.chatToken})
    : media = Map.unmodifiable(media),
      code = null;

  /// `errorData.code` of a refusal (`castEnd`, `needAdult`, `needLogin`,
  /// `needPassword`...; empty without one); null when accepted.
  final String? code;

  /// `media` of an accepted answer, checked to be the broadcaster's.
  final Map<String, Object?>? media;

  /// The first `PlayList` master (`hls3`, else `hls2`, else `hls`): an
  /// Amazon IVS playlist whose token can be read once.
  final Uri? master;

  /// `channel`: the chat channel (the broadcaster's number).
  final String? chatChannel;

  /// `token`: the chat token (valid about 30 minutes).
  final String? chatToken;

  /// Whether the answer was accepted and says the broadcast is live.
  bool get isLive => code == null && PandaLiveApi.flag(media?['isLive']) == true;
}

/// What a danmaku connection needs to join a live broadcast's chat (25-2;
/// the connection itself is M5's). 3.x had no PandaTV chat
/// (`EmptyDanmaku`).
///
/// The chat is a Centrifugo server ([PandaLiveApi.chatServer]) joined with
/// the guest token of `live/play` and subscribed to [channel]. Room entry
/// hands over the token its own `live/play` answer carried, without a
/// request; the token lasts about 30 minutes, so a later connection asks
/// `live/play` for broadcaster [userId] again ([PandaLiveApi.playForm]).
@immutable
final class PandaLiveDanmakuArgs {
  /// Creates the arguments.
  const new({required this.userId, required this.channel, this.token});

  /// The broadcaster's login id: `live/play` issues a fresh token for it.
  final String userId;

  /// The chat channel: `live/play`'s `channel`, the broadcaster's number.
  final String channel;

  /// `live/play`'s chat `token` (a JWT of about 30 minutes); null when the
  /// answer had none.
  final String? token;

  @override
  String toString() => 'PandaLiveDanmakuArgs($userId, $channel)';
}

/// What room entry keeps for playback (3.x kept its `PandaLiveRoom`
/// snapshot, streams included, in `data`): the qualities with their lines,
/// or why there is nothing to play. The chat arguments travel in the room's
/// `danmakuData` ([PandaLiveDanmakuArgs]).
@immutable
final class PandaLiveRoomData {
  /// Creates the data; [unavailable] is required when [qualities] is empty.
  new({required this.userId, required this.userIndex, List<LivePlayQuality> qualities = const [], this.unavailable})
    : qualities = List.unmodifiable(qualities),
      assert(qualities.isNotEmpty || unavailable != null, 'an empty playback needs its reason');

  /// The broadcaster the data belongs to (compared without case, as 3.x).
  final String userId;

  /// `bjInfo.idx`.
  final int userIndex;

  /// Best first; each quality's `data` is its `List<LivePlayLine>`.
  final List<LivePlayQuality> qualities;

  /// Why there is nothing to play: not live, ended, adult, password, fans
  /// only, no HLS.
  final SiteError? unavailable;
}

/// Pure parsing of PandaTV (팬더티비) responses (3.x's `PandaLiveApi`,
/// `PandaLiveLink` and the card rules of `PandaLiveSite`). Each function
/// takes the response text and status and returns 3.x's models or throws a
/// `SiteError`.
///
/// Anonymous and public: every API call is a form POST to
/// `api.pandalive.co.kr` from the website's origin. A room is a
/// broadcaster, its id the login id `userId` (`daisy00`; social logins carry
/// a suffix, `1506087545@ka`). Answers are `{result, message, ...}`; the
/// platform puts its refusals (no such broadcaster, broadcast ended, adult)
/// in HTTP 400 answers of the same shape.
abstract final class PandaLiveApi {
  /// The API host.
  static const String apiHost = 'api.pandalive.co.kr';

  /// The website.
  static const String origin = 'https://www.pandalive.co.kr';

  /// 3.x's desktop Chrome UA.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// 3.x's request headers (`requestHeaders`), for the API and the IVS
  /// master alike; [referer] is the page the request stands for.
  static Map<String, String> headers(String referer) => {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'ko-KR,ko;q=0.9,en;q=0.8',
    'origin': origin,
    'referer': referer,
  };

  /// Media request headers of broadcaster [userId] (3.x's `mediaHeaders`,
  /// which its `PlaybackHeaderResolver` sent for PandaTV): Amazon IVS
  /// refuses playlists and segments without the website's origin
  /// (REG-PANDALIVE-003).
  static Map<String, String> mediaHeaders(String userId) => {
    'user-agent': userAgent,
    'origin': origin,
    'referer': roomUrl(userId),
  };

  /// The largest API answer read (3.x's `responseLimit`, 4 MiB).
  static const int responseLimit = 4 * 1024 * 1024;

  /// The largest master playlist read (3.x's `manifestLimit`, 1 MiB).
  static const int manifestLimit = 1024 * 1024;

  /// Display name (3.x's `PandaLiveSite.name`).
  static const String categoryName = 'PandaTV';

  /// The id of 3.x's area, the public directory by popularity.
  static const String publicAreaId = 'public';

  /// The public area's name (3.x's zh.json `pandalive_public_directory`).
  static const String directoryAreaName = '公开直播';

  /// The id of the new-broadcaster area (25-1): the website's list of
  /// broadcasters the platform marks as new (`onlyNewBj=Y`).
  static const String newBroadcasterAreaId = 'newbj';

  /// The new-broadcaster area's name (25-1).
  static const String newBroadcasterAreaName = '新人主播';

  /// The directory notice's text, key `pandalive_directory_scope` (25-7:
  /// 3.x's text spoke of "native offsets" and a "BJ list").
  static const String directoryScope =
      '公开直播是 PandaTV 官网正在直播的公开房间，按人气排序；新人主播是平台标出的新主播。搜索会同时查找直播标题和主播，未开播的主播也会列出；也可以输入主播 ID，或粘贴 PandaTV 的直播间、频道链接。';

  /// The notice of a public room, key `pandalive_chat_notice` (25-7: 3.x's
  /// "remote chat pending; the user field is shown as ... playCnt is not
  /// concurrency" was a development note; the audience now shows `user`
  /// and `playCnt`, 25-3). Chat is shown since M5.21.
  static const String chatNotice = '人数分别是正在观看和本场累计观看。';

  /// The notice of an adult room, key `pandalive_adult_notice` (25-7).
  static const String adultNotice = '成人直播需要登录 PandaTV 并通过本人认证，本应用暂时无法播放。';

  /// The notice of a password room, key `pandalive_password_notice` (25-7).
  static const String passwordNotice = '这个直播间设了密码，本应用暂时无法播放。';

  /// The notice of a fans-only room (`type` `fan`; new with the
  /// restriction kinds of the unified rules).
  static const String fansNotice = '这个直播间只对粉丝开放，本应用暂时无法播放。';

  /// The notice of a room with other access conditions, key
  /// `pandalive_restricted_notice` (25-7).
  static const String restrictedNotice = '这个直播间有观看限制（例如需要登录），本应用暂时无法播放。';

  /// Names of the platform's category codes (25-8). PandaTV has no name
  /// service and its website shows no category, so these translate the
  /// codes themselves; `ind` is its individual (개인방송) broadcasting,
  /// which the site names itself for. Codes not listed are shown as sent.
  static const Map<String, String> areaNames = {
    'ind': '个人直播',
    'talk': '聊天',
    'music': '音乐',
    'game': '游戏',
    'sports': '体育',
    'etc': '其他',
  };

  /// The name of category code [code] ([areaNames]; an unknown code as
  /// sent, trimmed; empty for none).
  static String areaNameOf(Object? code) {
    final text = _text(code);
    return areaNames[text.toLowerCase()] ?? text;
  }

  /// The name of a video variant that is the broadcast's source rendition
  /// (`VIDEO="chunked"`; 25-5, the unified quality naming).
  static const String originalQualityName = '原画';

  /// Added to the source rendition's `sort`, so it ranks first (25-5).
  static const int sourceRank = 10000000000000;

  /// The chat server (the website's `newChat.node`), for M5 (25-2).
  static final Uri chatServer = Uri.parse('wss://chat-ws.neolive.kr/connection/websocket');

  /// Rows of a directory page (3.x's `directory` size).
  static const int pageSize = 30;

  /// The last page asked for (3.x).
  static const int maxPage = 1000;

  /// Rows asked of one search source at most (3.x).
  static const int maxSourceSize = 50;

  /// Rows of one answer at most (3.x).
  static const int maxRows = 64;

  /// The shortest keyword searched (3.x).
  static const int minKeywordLength = 2;

  /// The longest keyword searched (3.x).
  static const int maxKeywordLength = 100;

  /// How long after `live/play` a variant playlist is renewed: IVS variant
  /// URLs were still served 34 minutes after issue and refused (403) after
  /// 87, and an expired one stops the playlist (REG-PANDALIVE-005).
  static const Duration variantRefresh = Duration(minutes: 30);

  /// The line id of the IVS variants.
  static const String lineId = 'ivs';

  static final RegExp _userId = RegExp(r'^[A-Za-z0-9_]{1,64}(?:@[A-Za-z0-9_]{2,16})?$');

  /// [value] as a broadcaster id (3.x's `normalizeUserId`): trimmed, letters,
  /// digits and `_`, with an optional social-login suffix (`@ka`); null for
  /// anything else.
  static String? normalizeUserId(Object? value) {
    if (value is! String) return null;
    final id = value.trim();
    return _userId.hasMatch(id) ? id : null;
  }

  /// The live page of [userId]: the room's `link`, what the room opens
  /// outside the app and the Referer of its requests. The website's
  /// current `/play/<id>` (25-4; 3.x's `/live/play/<id>` redirects there).
  static String roomUrl(String userId) => Uri.https('www.pandalive.co.kr', '/play/$userId').toString();

  static final RegExp _koreanTime = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$');

  static const Duration _kst = Duration(hours: 9);

  /// A PandaTV time (`startTime`, `2026-09-28 02:00:35`) in UTC (25-12,
  /// REG-PANDALIVE-004): the platform writes Korean time (UTC+9) without a
  /// zone. Null for `0000-00-00 00:00:00`, a malformed or impossible date,
  /// and anything before 2000.
  static DateTime? koreanTime(Object? value) {
    final match = _koreanTime.firstMatch(_text(value));
    if (match == null) return null;
    final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
    final local = DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
    if (local.month != parts[1] || local.day != parts[2] || local.hour != parts[3] || local.minute != parts[4]) {
      return null;
    }
    final utc = local.subtract(_kst);
    return utc.year >= 2000 ? utc : null;
  }

  // Answers -------------------------------------------------------------------

  /// The failure of an answer's status: 401/403 refused, 404 missing, 429
  /// throttled, 5xx and anything else (3xx included: redirects are not
  /// followed) a network failure. Null for 200 and for 400, whose JSON says
  /// why (REG-PANDALIVE-001: 3.x dropped it and called every 400 a shape
  /// error).
  static SiteError? statusError(int status, String what) => switch (status) {
    200 || 400 => null,
    401 || 403 => RiskControl(_site, detail: '$what: HTTP $status'),
    404 => NotFound(_site, '$what: HTTP 404'),
    429 => RateLimited(_site, detail: '$what: HTTP 429'),
    _ => NetworkFailure(_site, '$what: HTTP $status'),
  };

  /// An API answer as a JSON object with a boolean `result`.
  static Map<String, dynamic> answer(String body, {required String what, int status = 200}) {
    if (statusError(status, what) case final error?) throw error;
    if (body.length > responseLimit) throw ApiChanged(_site, '$what: answer over $responseLimit characters');
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: HTTP $status, not JSON');
    }
    if (decoded is! Map) throw ApiChanged(_site, '$what: not a JSON object');
    final data = decoded.map((key, value) => MapEntry('$key', value));
    if (data['result'] is! bool) throw ApiChanged(_site, '$what: no result flag');
    return data;
  }

  /// A successful answer, or the typed refusal (see [refusal]).
  static Map<String, dynamic> ok(String body, {required String what, int status = 200}) {
    final data = answer(body, what: what, status: status);
    if (data['result'] == true) return data;
    throw refusal(data, what: what);
  }

  /// `errorData.code` of a refused answer, empty without one.
  static String refusalCode(Map<String, dynamic> data) {
    final errorData = data['errorData'];
    return errorData is Map ? _text(errorData['code']) : '';
  }

  /// The error of a refused answer: `유저 정보가 없습니다` (no such
  /// broadcaster) `NotFound`, an adult or fans-only broadcast (`needAdult`,
  /// `needLogin`) `NeedsLogin`, another code `StreamUnavailable`, a refusal
  /// without a code `ApiChanged`.
  static SiteError refusal(Map<String, dynamic> data, {required String what}) {
    final message = _text(data['message']);
    final code = refusalCode(data);
    if (message.contains('유저 정보가 없습니다')) return NotFound(_site, '$what: no such broadcaster');
    return switch (code) {
      '' => ApiChanged(_site, '$what refused: $message'),
      'needAdult' || 'needLogin' => NeedsLogin(_site, '$what: $code'),
      _ => StreamUnavailable(_site, '$what: $code'),
    };
  }

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? value.map((key, value) => MapEntry('$key', value)) : null;

  static String _text(Object? value) => value is String ? value.trim() : '';

  static String _firstText(Iterable<Object?> values) {
    for (final value in values) {
      final text = _text(value);
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  /// A PandaTV flag as 3.x read it: a boolean, `Y`/`N` or 1/0; null for
  /// anything else (3.x refused the answer).
  static bool? flag(Object? value) => switch (value) {
    final bool flag => flag,
    'Y' || 'y' || 1 => true,
    'N' || 'n' || 0 => false,
    _ => null,
  };

  static int? _positive(Object? value) {
    final number = jsonInt(value);
    return number != null && number > 0 ? number : null;
  }

  static String _count(Object? value) => jsonCount(value)?.toString() ?? '';

  /// An image as 3.x accepted it: an https URL on a `pandalive.co.kr`
  /// subdomain without user info; else empty (3.x refused the answer).
  static String image(Object? value) {
    final text = _text(value);
    if (text.isEmpty || text.length > 8192) return '';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) return '';
    return uri.host.toLowerCase().endsWith('.pandalive.co.kr') ? uri.toString() : '';
  }

  /// Whether [media]'s broadcaster is [userId] (without case) and, when
  /// given, number [index].
  static bool _owns(Map<String, Object?> media, String userId, [int? index]) =>
      normalizeUserId(media['userId'])?.toLowerCase() == userId.toLowerCase() &&
      (index == null || _positive(media['userIdx']) == index);

  /// Whether an on-air broadcast is a recording played again (`onAirType`
  /// or `liveType` `rec`; its title starts with `[녹]`, 녹화): a replay, as
  /// Twitch's reruns (the unified rule on replays and reruns; 9 of 132
  /// broadcasts of the directory on 2026-09-28; 3.x showed them live). It
  /// plays like a live broadcast.
  static bool isRerun(Map<String, Object?> media) =>
      _text(media['onAirType']) == 'rec' || _text(media['liveType']) == 'rec';

  /// The state of an on-air broadcast: a replay for a rerun ([isRerun]),
  /// else live.
  static LiveStatus _onAir(Map<String, Object?> media) => isRerun(media) ? LiveStatus.replay : LiveStatus.live;

  // Restrictions --------------------------------------------------------------

  /// The restriction a broadcast's flags show (the unified rules): adult
  /// (`isAdult`), else a password (`isPw`), else fans only (`type` `fan`),
  /// else none for a free broadcast (`type` `free`); null when its `type`
  /// says neither (not known).
  static LiveRestriction? restrictionOf(Map<String, Object?> media) {
    if (flag(media['isAdult']) ?? false) return LiveRestriction.adult;
    if (flag(media['isPw']) ?? false) return LiveRestriction.password;
    return switch (_text(media['type'])) {
      'fan' => LiveRestriction.subscribersOnly,
      'free' => LiveRestriction.none,
      _ => null,
    };
  }

  /// The restriction of a `live/play` refusal with [code] (not `castEnd`)
  /// of a broadcast listed with [media]: the code when it says (`needAdult`
  /// adult, `needPassword`/`password` a password), else the broadcast's
  /// flags (an anonymous viewer of a password room is refused `needLogin`,
  /// 2026-09-29), else `needLogin` needs a login and any other code is
  /// unplayable.
  static LiveRestriction refusalRestriction(String code, Map<String, Object?>? media) {
    switch (code) {
      case 'needAdult':
        return LiveRestriction.adult;
      case 'needPassword' || 'password':
        return LiveRestriction.password;
    }
    final flagged = media == null ? null : restrictionOf(media);
    if (flagged != null && flagged != LiveRestriction.none) return flagged;
    return code == 'needLogin' ? LiveRestriction.needsLogin : LiveRestriction.unplayable;
  }

  /// Why a broadcast with [restriction] cannot be played (M2.1's table):
  /// adult and login `NeedsLogin`, the rest `StreamUnavailable` naming it.
  static SiteError restrictionError(LiveRestriction restriction, String what) => switch (restriction) {
    LiveRestriction.adult || LiveRestriction.needsLogin => NeedsLogin(_site, '$what (${restriction.name})'),
    _ => StreamUnavailable(_site, '$what (${restriction.name})'),
  };

  /// The notice of a broadcast with [restriction]: adult, password, fans
  /// only, other conditions, else (none, or not known) the chat notice.
  static String noticeOf(LiveRestriction? restriction) => switch (restriction) {
    LiveRestriction.adult => adultNotice,
    LiveRestriction.password => passwordNotice,
    LiveRestriction.subscribersOnly => fansNotice,
    LiveRestriction.none || null => chatNotice,
    _ => restrictedNotice,
  };

  // Catalog and directory -----------------------------------------------------

  /// The catalog: one category, PandaTV, with 3.x's public directory by
  /// popularity and the new broadcasters (25-1), both by popularity.
  static List<LiveCategory> categories() => [
    LiveCategory(
      id: _site,
      name: categoryName,
      children: const [
        LiveArea(
          platform: _site,
          areaType: 'directory',
          typeName: categoryName,
          areaId: publicAreaId,
          areaName: directoryAreaName,
        ),
        LiveArea(
          platform: _site,
          areaType: 'directory',
          typeName: categoryName,
          areaId: newBroadcasterAreaId,
          areaName: newBroadcasterAreaName,
        ),
      ],
    ),
  ];

  /// The area id of [area]: [publicAreaId] for null (the directory, as
  /// 3.x) or the public area, [newBroadcasterAreaId] for the new
  /// broadcasters; anything else is a caller error (3.x refused it before
  /// any request).
  static String checkArea(LiveArea? area) {
    if (area == null) return publicAreaId;
    if (area.platform != _site ||
        area.areaType != 'directory' ||
        (area.areaId != publicAreaId && area.areaId != newBroadcasterAreaId)) {
      throw ArgumentError.value(area, 'category', 'not a PandaTV directory');
    }
    return area.areaId;
  }

  /// Checks a page number as 3.x did before any request (1–[maxPage]).
  static void checkPage(int page) {
    if (page < 1 || page > maxPage) throw RangeError.range(page, 1, maxPage, 'page');
  }

  /// Checks a search keyword (already trimmed) as 3.x did before any
  /// request: no control character.
  static void checkKeyword(String keyword) {
    if (RegExp(r'[\x00-\x1f]').hasMatch(keyword)) {
      throw ArgumentError.value(keyword, 'keyword', 'contains a control character');
    }
  }

  /// The form of `live/index` for directory page [page] of area [areaId]
  /// (3.x): [pageSize] rows by popularity; the new broadcasters add
  /// `onlyNewBj=Y` (25-1, as the website and `S02-index-newbj`).
  static Map<String, String> directoryForm(int page, {String areaId = publicAreaId}) => {
    'offset': '${(page - 1) * pageSize}',
    'limit': '$pageSize',
    'orderBy': 'hot',
    if (areaId == newBroadcasterAreaId) 'onlyNewBj': 'Y',
  };

  /// The rows of a paged answer asked at [page] of [size] (3.x's
  /// `_pagedRows`): `page.offset`, `limit` and `page` must be what was
  /// asked, `total` a count, and `list` at most [maxRows] rows; more pages
  /// while the rows so far are fewer than `total`.
  static ({List<Object?> rows, bool hasMore}) _rows(
    Map<String, dynamic> data, {
    required int page,
    required int size,
    required String what,
  }) {
    final paging = _map(data['page']);
    final offset = (page - 1) * size;
    if (paging == null ||
        jsonInt(paging['offset']) != offset ||
        jsonInt(paging['limit']) != size ||
        jsonInt(paging['page']) != page) {
      throw ApiChanged(_site, '$what: page ${data['page']} for offset $offset, limit $size');
    }
    final total = jsonCount(paging['total']);
    if (total == null) throw ApiChanged(_site, '$what: page.total ${paging['total']}');
    final rows = data['list'];
    if (rows is! List || rows.length > maxRows) throw ApiChanged(_site, '$what: list is not a list of $maxRows rows');
    return (rows: rows, hasMore: offset + rows.length < total);
  }

  /// A page of live broadcasts (`live/index`: the directory and the LIVE
  /// search) asked at [page] of [size]: 3.x's live cards, a broadcaster
  /// once.
  ///
  /// Unlike 3.x, a row that cannot be a live card (no broadcaster id, not
  /// live) is skipped instead of failing the page, an empty title is the
  /// nick, and a field 3.x refused is left empty.
  static LiveDirectoryPage livePage(String body, {required int page, int size = pageSize, int status = 200}) {
    const what = 'live/index';
    final data = ok(body, what: what, status: status);
    final (:rows, :hasMore) = _rows(data, page: page, size: size, what: what);
    final seen = <String>{};
    return LiveDirectoryPage(
      page: page,
      hasMore: hasMore,
      rooms: [
        for (final row in rows)
          if (_map(row) case final row?)
            if (liveCard(row) case final card? when seen.add(card.roomId.toLowerCase())) card,
      ],
    );
  }

  /// A live card (3.x's `parseCard` and `_directoryCard`): the broadcast
  /// title (else the nick), the broadcaster's nick, number and avatar, the
  /// snapshot as cover, the category's name as area (25-8), concurrent
  /// viewers, this broadcast's entries as cumulative viewers (`playCnt`,
  /// 25-3), fans, the start (25-12) and the restriction its flags show,
  /// with that restriction's notice; live, or a replay for a rerun
  /// ([isRerun]). Null for a row without a broadcaster id or that is not
  /// on air.
  ///
  /// The card's `userId` is the broadcaster's number, as in room details
  /// and the BJ search (25-10; 3.x wrote the login id here); empty without
  /// a number. An empty nick stays empty (the unified rule on
  /// placeholders; M4.25 wrote the id).
  static LiveRoom? liveCard(Map<String, Object?> row) {
    final id = normalizeUserId(row['userId']);
    if (id == null || flag(row['isLive']) != true) return null;
    final nick = _text(row['userNick']);
    final restriction = restrictionOf(row);
    return LiveRoom(
      platform: _site,
      roomId: id,
      userId: _positive(row['userIdx'])?.toString() ?? '',
      title: _firstText([row['title'], nick]),
      nick: nick,
      avatar: image(row['userImg']),
      cover: image(row['thumbUrl'] ?? row['ivsThumbnail']),
      area: areaNameOf(row['category']),
      link: roomUrl(id),
      liveStatus: _onAir(row),
      startedAt: koreanTime(row['startTime']),
      restriction: restriction,
      onlineViewers: _count(row['user']),
      totalViewers: _count(row['playCnt']),
      followers: _count(row['fanCnt']),
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: noticeOf(restriction),
    );
  }

  // Search --------------------------------------------------------------------

  /// The form of the LIVE search (`live/index` by viewers, 3.x).
  static Map<String, String> liveSearchForm(String keyword, {required int page, required int size}) => {
    'offset': '${(page - 1) * size}',
    'limit': '$size',
    'orderBy': 'user',
    'searchVal': keyword,
  };

  /// The form of the BJ search (`live/bj_list`, 3.x).
  static Map<String, String> broadcasterSearchForm(String keyword, {required int page, required int size}) => {
    'offset': '${(page - 1) * size}',
    'limit': '$size',
    'searchVal': keyword,
  };

  /// The page of the website a search source stands for (3.x's Referer).
  static String searchReferer(String source, String keyword) =>
      '$origin/search/$source?text=${Uri.encodeQueryComponent(keyword)}';

  /// A page of the BJ search (`live/bj_list`) asked at [page] of [size]:
  /// broadcasters live or not (3.x's `parseSearchProfile` as a room).
  ///
  /// As 3.x, a row is skipped when the service blocked it
  /// (`blockService`), without a broadcaster id or number, or with a
  /// `media` that is not the broadcaster's; unlike 3.x, a row whose other
  /// fields 3.x refused is kept with those fields empty.
  static LiveDirectoryPage broadcasterPage(String body, {required int page, required int size, int status = 200}) {
    const what = 'live/bj_list';
    final data = ok(body, what: what, status: status);
    final (:rows, :hasMore) = _rows(data, page: page, size: size, what: what);
    return LiveDirectoryPage(
      page: page,
      hasMore: hasMore,
      rooms: [
        for (final row in rows)
          if (_map(row) case final row?) ?profileCard(row),
      ],
    );
  }

  /// A broadcaster of the BJ search (see [broadcasterPage]): named by its
  /// nick, the avatar `thumbUrl`, 3.x's `userId` the broadcaster's number.
  /// Without `media` it is offline, titled by the nick; with it, the
  /// broadcast's title, cover, category name (25-8) and fans, live by
  /// `isLive` (a replay for a rerun, [isRerun]; unknown when it says
  /// neither). Only while on air: viewers,
  /// cumulative viewers (25-3), the start (25-12) and the restriction the
  /// flags show; the notice is the restriction's (3.x: adult, else
  /// password). An empty nick stays empty (the unified rule on
  /// placeholders).
  static LiveRoom? profileCard(Map<String, Object?> row) {
    if (flag(row['blockService']) == true) return null;
    final id = normalizeUserId(row['userId']);
    final index = _positive(row['userIdx']);
    if (id == null || index == null) return null;
    final nick = _text(row['userNick']);
    final avatar = image(row['thumbUrl']);
    final raw = row['media'];
    if (raw == null) {
      return LiveRoom(
        platform: _site,
        roomId: id,
        userId: '$index',
        title: nick,
        nick: nick,
        avatar: avatar,
        area: '',
        link: roomUrl(id),
        liveStatus: LiveStatus.offline,
        followers: '',
        introduction: '',
        audienceMetricType: AudienceMetricType.onlineViewers,
        notice: chatNotice,
      );
    }
    final media = _map(raw);
    if (media == null || !_owns(media, id, index)) return null;
    final live = flag(media['isLive']);
    final isLive = live ?? false;
    final restriction = restrictionOf(media);
    return LiveRoom(
      platform: _site,
      roomId: id,
      userId: '$index',
      title: _firstText([media['title'], nick]),
      nick: nick,
      avatar: avatar,
      cover: image(media['thumbUrl'] ?? media['ivsThumbnail']),
      area: areaNameOf(media['category']),
      link: roomUrl(id),
      liveStatus: switch (live) {
        true => _onAir(media),
        false => LiveStatus.offline,
        null => LiveStatus.unknown,
      },
      startedAt: isLive ? koreanTime(media['startTime']) : null,
      restriction: isLive ? restriction : null,
      onlineViewers: isLive ? _count(media['user']) : '',
      totalViewers: isLive ? _count(media['playCnt']) : '',
      followers: _count(media['fanCnt']),
      introduction: '',
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: noticeOf(restriction),
    );
  }

  // Rooms ---------------------------------------------------------------------

  /// The form of `member/bj`: the broadcaster and its broadcast (25-9; 3.x
  /// also asked for the fan grades, `info=media fanGrade`, and never read
  /// them).
  static Map<String, String> memberForm(String userId) => {'userId': userId, 'info': 'media'};

  /// The form of `live/play` (3.x; the website sends the same on each
  /// visit, which counts as a view).
  static Map<String, String> playForm(String userId) => {
    'action': 'watch',
    'userId': userId,
    'password': '',
    'shareLinkType': '',
  };

  /// Broadcaster [userId] from `member/bj`. No such broadcaster (HTTP 400,
  /// `유저 정보가 없습니다`) is `NotFound`; a `bjInfo` of another
  /// broadcaster or without a number, or a `media` that is not an object of
  /// this broadcaster, is `ApiChanged`.
  static PandaLiveMember member(String body, {required String userId, int status = 200}) {
    const what = 'member/bj';
    final data = ok(body, what: what, status: status);
    final info = _map(data['bjInfo']);
    if (info == null) throw const ApiChanged(_site, '$what: no bjInfo');
    final id = normalizeUserId(info['id']);
    if (id == null || id.toLowerCase() != userId.toLowerCase()) {
      throw ApiChanged(_site, '$what: bjInfo of ${info['id']} for $userId');
    }
    final index = _positive(info['idx']);
    if (index == null) throw ApiChanged(_site, '$what: bjInfo.idx ${info['idx']}');
    final raw = data['media'];
    final media = raw == null ? null : _map(raw);
    if (raw != null && (media == null || !_owns(media, userId, index))) {
      throw ApiChanged(_site, '$what: media of ${media?['userId']} for $userId');
    }
    return PandaLiveMember(userId: userId, index: index, profile: info, media: media);
  }

  /// `live/play` for [member]. A refusal (HTTP 400: ended, adult, fans
  /// only, password) is kept with its code for [playRoom]; an accepted
  /// answer must carry this broadcaster's `media` and, when live, a
  /// `PlayList` whose first usable master is an IVS URL (`ApiChanged` when
  /// it has masters and none is usable; none at all is null).
  static PandaLivePlay play(String body, {required PandaLiveMember member, int status = 200}) {
    const what = 'live/play';
    final data = answer(body, what: what, status: status);
    if (data['result'] != true) return PandaLivePlay.refused(refusalCode(data));
    final media = _map(data['media']);
    if (media == null || !_owns(media, member.userId, member.index)) {
      throw ApiChanged(_site, '$what: media of ${media?['userId']} for ${member.userId}');
    }
    if (flag(media['isLive']) != true) return PandaLivePlay.accepted(media: media);
    final playlist = _map(data['PlayList']);
    if (playlist == null) throw const ApiChanged(_site, '$what: no PlayList');
    return PandaLivePlay.accepted(
      media: media,
      master: _master(playlist),
      chatChannel: jsonString(data['channel']),
      chatToken: jsonString(data['token']),
    );
  }

  /// The first IVS master of `hls3`, `hls2`, `hls` in that order (3.x's
  /// `_firstMaster`); null when none has a URL. Unlike 3.x, a list or entry
  /// that is not usable (not a list, not an object, not an IVS playlist)
  /// is passed over for the next one (the unified rule: one bad address
  /// only loses itself); some and none usable is `ApiChanged`.
  static Uri? _master(Map<String, Object?> playlist) {
    String? broken;
    for (final key in const ['hls3', 'hls2', 'hls']) {
      final entries = playlist[key];
      if (entries == null) continue;
      if (entries is! List || entries.length > 16) {
        broken ??= 'PlayList.$key';
        continue;
      }
      for (final entry in entries) {
        final item = _map(entry);
        if (item == null) {
          broken ??= 'PlayList.$key item';
          continue;
        }
        final url = item['url'];
        if (url is String && url.isNotEmpty) {
          if (mediaUrl(url) case final master?) return master;
          broken ??= '$key is not an IVS playlist';
        }
      }
    }
    if (broken != null) throw ApiChanged(_site, 'live/play: $broken');
    return null;
  }

  /// [text] as an IVS playlist URL as 3.x accepted it: https on a
  /// `live-video.net` subdomain, a `.m3u8` path, no user info, fragment,
  /// blank or control character; else null.
  static Uri? mediaUrl(String text) {
    if (text.isEmpty || text.length > 65536 || RegExp(r'[\s\x00-\x1f]').hasMatch(text)) return null;
    final uri = Uri.tryParse(text);
    final host = uri?.host.toLowerCase() ?? '';
    if (uri == null ||
        uri.scheme.toLowerCase() != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !host.endsWith('.live-video.net') ||
        !uri.path.toLowerCase().endsWith('.m3u8')) {
      return null;
    }
    return uri;
  }

  /// The room of a broadcaster the platform lists as not live (3.x's
  /// `_profileRoom`): the channel title (else the nick), the banner as
  /// cover, the channel description, fans, offline. An empty nick stays
  /// empty (the unified rule on placeholders; M4.25 wrote the id).
  static LiveRoom profileRoom(PandaLiveMember member) {
    final profile = member.profile;
    final nick = _text(profile['nick']);
    return LiveRoom(
      platform: _site,
      roomId: member.userId,
      userId: '${member.index}',
      title: _firstText([profile['channelTitle'], nick]),
      nick: nick,
      avatar: image(profile['thumbUrl']),
      cover: image(profile['channelBannerUrl']),
      area: '',
      link: roomUrl(member.userId),
      liveStatus: LiveStatus.offline,
      followers: _count(profile['fanCnt']),
      introduction: _text(profile['channelDesc']),
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: chatNotice,
    );
  }

  /// The room of a broadcast (3.x's `_restrictedRoom` and `_liveRoom`): the
  /// broadcast's nick, title (else the channel title, else the nick),
  /// avatar, cover (the snapshot, for a playable broadcast also
  /// `ivsThumbnail`, else the banner), category name (25-8), fans, viewers
  /// and cumulative viewers (25-3), its start (25-12), with the channel
  /// description; live (a replay for a rerun, [isRerun]), with [notice]
  /// and [restriction]. An empty nick stays empty (the unified rule on
  /// placeholders).
  static LiveRoom mediaRoom(
    PandaLiveMember member,
    Map<String, Object?> media, {
    required String notice,
    LiveRestriction? restriction,
    bool playable = false,
  }) {
    final profile = member.profile;
    final nick = _firstText([media['userNick'] ?? profile['nick'], profile['nick']]);
    final cover = playable
        ? media['thumbUrl'] ?? media['ivsThumbnail'] ?? profile['channelBannerUrl']
        : media['thumbUrl'] ?? profile['channelBannerUrl'];
    return LiveRoom(
      platform: _site,
      roomId: member.userId,
      userId: '${member.index}',
      title: _firstText([media['title'], profile['channelTitle'], profile['nick'], nick]),
      nick: nick,
      avatar: image(media['userImg'] ?? profile['thumbUrl']),
      cover: image(cover),
      area: areaNameOf(media['category']),
      link: roomUrl(member.userId),
      liveStatus: _onAir(media),
      startedAt: koreanTime(media['startTime']),
      restriction: restriction,
      onlineViewers: _count(media['user']),
      totalViewers: _count(media['playCnt']),
      followers: _count(media['fanCnt'] ?? profile['fanCnt']),
      introduction: _text(profile['channelDesc']),
      audienceMetricType: AudienceMetricType.onlineViewers,
      notice: notice,
    );
  }

  /// Whether `member/bj` lists [member]'s broadcast as live: it has a
  /// `media` whose `isLive` is not false (25-6; 3.x took any `media` for a
  /// live broadcast; one that says neither is still live, as 3.x).
  static bool listedLive(PandaLiveMember member) => member.media != null && flag(member.media!['isLive']) != false;

  /// The room of a follow refresh and of the exact searches (3.x's `room`
  /// without media): not listed as live ([listedLive]) is [profileRoom];
  /// listed is the `member/bj` broadcast, live, with the restriction its
  /// flags show and that restriction's notice (3.x: always the chat
  /// notice).
  static LiveRoom refreshRoom(PandaLiveMember member) {
    if (!listedLive(member)) return profileRoom(member);
    final restriction = restrictionOf(member.media!);
    return mediaRoom(member, member.media!, notice: noticeOf(restriction), restriction: restriction);
  }

  /// The room of room entry from [member] and its [play] (3.x's `room`),
  /// and why it cannot be played when so:
  /// - ended (`castEnd`), or accepted as not live: [profileRoom], offline,
  ///   `StreamUnavailable`;
  /// - another refusal: the `member/bj` broadcast, live, with the
  ///   restriction of [refusalRestriction], its notice and its error
  ///   ([restrictionError]: adult and login `NeedsLogin`; password, fans
  ///   only and anything else `StreamUnavailable`);
  /// - accepted and live: the `live/play` broadcast with the chat notice,
  ///   without restriction; unplayable (`StreamUnavailable`) when it has
  ///   no HLS master (3.x failed the entry), else nothing yet (the master
  ///   decides).
  static ({LiveRoom room, SiteError? unavailable}) playRoom(PandaLiveMember member, PandaLivePlay play) {
    final code = play.code;
    if (code == 'castEnd') {
      return (room: profileRoom(member), unavailable: const StreamUnavailable(_site, 'live/play: castEnd'));
    }
    if (code != null) {
      final restriction = refusalRestriction(code, member.media);
      return (
        room: mediaRoom(member, member.media ?? const {}, notice: noticeOf(restriction), restriction: restriction),
        unavailable: restrictionError(restriction, 'live/play: ${code.isEmpty ? 'refused' : code}'),
      );
    }
    if (!play.isLive) {
      return (room: profileRoom(member), unavailable: const StreamUnavailable(_site, 'live/play: not live'));
    }
    if (play.master == null) {
      return (
        room: mediaRoom(
          member,
          play.media!,
          notice: chatNotice,
          restriction: LiveRestriction.unplayable,
          playable: true,
        ),
        unavailable: const StreamUnavailable(_site, 'live/play: no HLS'),
      );
    }
    return (
      room: mediaRoom(member, play.media!, notice: chatNotice, restriction: LiveRestriction.none, playable: true),
      unavailable: null,
    );
  }

  /// The chat arguments of room entry (25-2): an accepted, live [play]'s
  /// channel (the broadcaster's number when it has none, or one that is
  /// not a number) and token; null for a refused or not live answer, which
  /// has no token.
  static PandaLiveDanmakuArgs? danmakuArgs(PandaLiveMember member, PandaLivePlay play) {
    if (!play.isLive) return null;
    final channel = play.chatChannel;
    return PandaLiveDanmakuArgs(
      userId: member.userId,
      channel: channel != null && RegExp(r'^[0-9]{1,19}$').hasMatch(channel) ? channel : '${member.index}',
      token: play.chatToken,
    );
  }

  // Streams -------------------------------------------------------------------

  /// A master playlist answer: its text, or the failure. The master is part
  /// of the broadcast, so a missing one (404) means the stream is gone; its
  /// token is single use, so a second read is refused (403, RiskControl:
  /// REG-PANDALIVE-002).
  static String master(String body, {int status = 200}) {
    const what = 'IVS master';
    if (status == 404) throw const StreamUnavailable(_site, '$what: HTTP 404');
    if (status == 400) throw const ApiChanged(_site, '$what: HTTP 400');
    if (statusError(status, what) case final error?) throw error;
    if (body.length > manifestLimit) throw const ApiChanged(_site, '$what: over $manifestLimit characters');
    return body;
  }

  /// The qualities of an IVS master read once (3.x's `parseManifest`,
  /// REG-PANDALIVE-002): one per video variant, id `<height>p`, plus `60`
  /// from 50 fps (25-5: 3.x also wrote `30` from 25 fps; a repeated id
  /// still gets `_<n>`, n counting the video variants in the master's
  /// order); the source rendition (`VIDEO="chunked"`) named
  /// [originalQualityName], the others by their id (3.x: `<id> · HLS`).
  /// Best first: the source, then by height, frame rate, bandwidth; `sort`
  /// is height × 10⁷ + bandwidth, plus [sourceRank] for the source. Each
  /// quality holds one line (`data`): the variant playlist, with
  /// [mediaHeaders], HLS, the codec of `CODECS`, [lineId] and the lease of
  /// [issuedAt] (see [lease]). [qualityIdFromLegacy] maps 3.x's ids.
  ///
  /// The master is read by the shared [HlsStreamInf.read] with lenient
  /// attributes (one reading with YouTube's, M7.1 notes); a tag between a
  /// variant and its URI no longer loses the variant. As 3.x, a text that
  /// is not a master is `ApiChanged`, and a variant without a resolution
  /// (audio only) is left out. Unlike 3.x, a variant
  /// without its URI, with a frame rate or bandwidth out of range, or whose
  /// URL is not IVS only loses itself (the unified rule); none left is
  /// `ApiChanged` when some were such, else `StreamUnavailable`.
  static List<LivePlayQuality> qualities(
    String body, {
    required Uri master,
    required String userId,
    required DateTime issuedAt,
  }) {
    const what = 'IVS master';
    if (mediaUrl('$master') == null) throw ApiChanged(_site, '$what: $master is not an IVS playlist');
    final List<HlsStreamInf> entries;
    try {
      if (body.length > manifestLimit) throw const FormatException('over the limit');
      entries = HlsStreamInf.read(body);
    } on FormatException {
      throw const ApiChanged(_site, '$what: not a playlist');
    }
    final variants =
        <({String id, bool source, int height, double frameRate, int bandwidth, Uri url, String? codec})>[];
    final ids = <String>{};
    var count = 0;
    String? broken;
    for (final entry in entries) {
      final attributes = entry.attributes();
      final uri = entry.uri;
      if (uri == null) {
        broken ??= 'a variant without its URI';
        continue;
      }
      final resolution = attributes['RESOLUTION'];
      final match = resolution == null ? null : RegExp(r'^[1-9][0-9]{1,4}x([1-9][0-9]{1,4})$').firstMatch(resolution);
      if (match == null) continue;
      final height = int.parse(match.group(1)!);
      final frameRate = double.tryParse(attributes['FRAME-RATE'] ?? '') ?? 0;
      final bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0;
      if (frameRate < 0 || frameRate > 240 || bandwidth < 0) {
        broken ??= 'frame rate $frameRate, bandwidth $bandwidth';
        continue;
      }
      Uri? url;
      try {
        url = mediaUrl('${master.resolve(uri)}');
      } on FormatException {
        url = null;
      }
      if (url == null) {
        broken ??= 'a variant that is not an IVS playlist';
        continue;
      }
      final label = '${height}p${frameRate >= 50 ? '60' : ''}';
      count++;
      variants.add((
        id: ids.add(label) ? label : '${label}_$count',
        source: attributes['VIDEO'] == 'chunked',
        height: height,
        frameRate: frameRate,
        bandwidth: bandwidth,
        url: url,
        codec: _codecOf(attributes['CODECS']),
      ));
    }
    if (variants.isEmpty) {
      if (broken != null) throw ApiChanged(_site, '$what: no usable variant ($broken)');
      throw const StreamUnavailable(_site, '$what: no video variant');
    }
    variants.sort((left, right) {
      if (left.source != right.source) return left.source ? -1 : 1;
      final height = right.height.compareTo(left.height);
      if (height != 0) return height;
      final fps = right.frameRate.compareTo(left.frameRate);
      return fps != 0 ? fps : right.bandwidth.compareTo(left.bandwidth);
    });
    final headers = mediaHeaders(userId);
    return List.unmodifiable([
      for (final variant in variants)
        LivePlayQuality(
          quality: variant.source ? originalQualityName : variant.id,
          id: variant.id,
          sort: (variant.source ? sourceRank : 0) + variant.height * 10000000 + variant.bandwidth,
          data: List<LivePlayLine>.unmodifiable([
            LivePlayLine(
              '${variant.url}',
              headers: headers,
              format: StreamFormat.hls,
              codec: variant.codec,
              lineId: lineId,
              lease: lease(issuedAt),
            ),
          ]),
        ),
    ]);
  }

  /// A variant's lease: renewed [variantRefresh] after `live/play` issued
  /// it (REG-PANDALIVE-005). The token is opaque, so the expiry is not
  /// known; an expired playlist stops playback, so the renewal cuts over.
  /// (3.x had no lease: it fetched the room again after a failure.)
  static PlayLease lease(DateTime issuedAt) => PlayLease(refreshAt: issuedAt.add(variantRefresh), cutsConnection: true);

  static String? _codecOf(String? codecs) {
    for (final name in (codecs ?? '').split(',')) {
      final codec = name.trim().toLowerCase();
      if (codec.startsWith('avc1') || codec.startsWith('avc3')) return 'avc';
      if (codec.startsWith('hvc1') || codec.startsWith('hev1')) return 'hevc';
    }
    return null;
  }

  /// [data]'s qualities, or why there are none.
  static List<LivePlayQuality> playQualities(PandaLiveRoomData data) {
    if (data.qualities.isNotEmpty) return data.qualities;
    throw data.unavailable ?? const StreamUnavailable(_site, 'no quality');
  }

  static final RegExp _legacyQualityId = RegExp(r'^([1-9][0-9]{1,4})p30(_[0-9]+)?$');

  /// The quality id for [id] as stored before 25-5: 3.x's `<height>p30`
  /// (25 to 49 fps) is now `<height>p`, and its repeated `<height>p30_<n>`
  /// `<height>p_<n>`; every other id (`<height>p60`, `<height>p`, …) is kept
  /// as it is. Trimmed; applying it twice changes nothing.
  static String qualityIdFromLegacy(String id) {
    final text = id.trim();
    final match = _legacyQualityId.firstMatch(text);
    return match == null ? text : '${match.group(1)}p${match.group(2) ?? ''}';
  }

  /// The line of [quality] (by its id; a 3.x id is read as the new one,
  /// [qualityIdFromLegacy]) among [data]'s qualities, applied as the new
  /// id; a quality the broadcast does not offer is `StreamUnavailable`, and
  /// a room with nothing to play says why.
  static LivePlayUrlResolution resolution(PandaLiveRoomData data, LivePlayQuality quality) {
    final wanted = qualityIdFromLegacy('${quality.selectionId}');
    final match = playQualities(data).where((option) => '${option.selectionId}' == wanted).firstOrNull;
    if (match == null) throw StreamUnavailable(_site, 'quality $wanted is not offered');
    return LivePlayUrlResolution.lines(match.data! as List<LivePlayLine>, appliedQualityData: match.selectionId);
  }

  // Links ---------------------------------------------------------------------

  /// Hosts of room links (3.x).
  static const Set<String> hosts = {'pandalive.co.kr', 'www.pandalive.co.kr', 'm.pandalive.co.kr'};

  /// The broadcaster of a room link (3.x's `PandaLiveLink.parse`): http(s)
  /// on [hosts] with the default port, without user info, fragment, blank
  /// or control character, the path (empty segments ignored, `live`,
  /// `play`, `channel`, `home` in any case) `/live/play/<id>`,
  /// `/channel/<id>` or `/channel/<id>/home`, and the website's live page
  /// `/play/<id>` (to which `/live/play/<id>` now redirects; 3.x did not
  /// know it). The id as written; null for anything else, a path that does
  /// not decode included (3.x threw).
  static String? roomIdFromUrl(String url) {
    if (url.length > 8192 || RegExp(r'[\x00-\x20\x7f]').hasMatch(url)) return null;
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) ||
        !hosts.contains(uri.host.toLowerCase())) {
      return null;
    }
    final List<String> segments;
    try {
      segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    } on FormatException {
      return null;
    }
    final id = switch ([for (final segment in segments) segment.toLowerCase()]) {
      ['live', 'play', _] => segments[2],
      ['play', _] || ['channel', _] || ['channel', _, 'home'] => segments[1],
      _ => null,
    };
    return normalizeUserId(id);
  }
}
