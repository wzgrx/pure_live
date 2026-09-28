import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:live_core/src/audience.dart';
import 'package:live_core/src/json.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:meta/meta.dart';

const _site = 'liveme';

/// What a LiveMe link names.
enum LiveMeLinkKind {
  /// A room: the anchor's short id, the room identity.
  shortId,

  /// An anchor's user id (`/u/<uid>`); its short id is in `user/getinfo`.
  userId,

  /// One broadcast (`/v/<vid>`, the `shareurl` page `/m/v/<vid>/index.html`);
  /// its short id is in `live/queryinfosimple`.
  videoId,
}

/// A LiveMe link (3.x's `LiveMeLink`): a room page, an anchor page or a
/// broadcast's share page on `liveme.com` or `www.liveme.com`.
@immutable
final class LiveMeLink {
  /// Creates a link.
  const new(this.kind, this.id);

  /// Room, anchor or broadcast.
  final LiveMeLinkKind kind;

  /// The short id, user id or video id.
  final String id;

  static final RegExp _shortId = RegExp(r'^[1-9][0-9]{4,11}$');
  static final RegExp _longId = RegExp(r'^[1-9][0-9]{12,23}$');
  static final RegExp _locale = RegExp(r'^[a-z]{2}(?:-[a-z]{2,4})?$', caseSensitive: false);

  /// The link [raw] is, exactly as 3.x read it, or null: http(s) on
  /// `liveme.com` or `www.liveme.com` (any port, no user info), an optional
  /// locale segment first (`us`, `zh-tw`), then
  /// - `livehot/streaming/<short id>`: a room;
  /// - `u/<user id>`: an anchor;
  /// - `v/<video id>` or `m/v/<video id>/index.html`: a broadcast.
  ///
  /// Words are matched in any case; query and fragment are ignored. A path
  /// that does not decode is no link (3.x threw a `FormatException`).
  static LiveMeLink? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        (uri.host.toLowerCase() != 'liveme.com' && uri.host.toLowerCase() != 'www.liveme.com')) {
      return null;
    }
    final List<String> segments;
    try {
      segments = uri.pathSegments.where((value) => value.isNotEmpty).toList(growable: false);
    } on FormatException {
      return null;
    }
    if (segments.isEmpty || segments.any((value) => value == '.' || value == '..')) return null;
    final tail = _locale.hasMatch(segments.first) ? segments.sublist(1) : segments;
    final words = [for (final segment in tail) segment.toLowerCase()];
    switch (words) {
      case ['livehot', 'streaming', _]:
        final id = normalizeShortId(tail[2]);
        return id == null ? null : LiveMeLink(LiveMeLinkKind.shortId, id);
      case ['u', _]:
        final id = normalizeLongId(tail[1]);
        return id == null ? null : LiveMeLink(LiveMeLinkKind.userId, id);
      case ['v', _]:
        final id = normalizeLongId(tail[1]);
        return id == null ? null : LiveMeLink(LiveMeLinkKind.videoId, id);
      case ['m', 'v', _, 'index.html']:
        final id = normalizeLongId(tail[2]);
        return id == null ? null : LiveMeLink(LiveMeLinkKind.videoId, id);
    }
    return null;
  }

  /// [parse], else a bare short id (what 3.x's search looked up directly).
  static LiveMeLink? parseOrShortId(String raw) {
    final parsed = parse(raw);
    if (parsed != null) return parsed;
    final id = normalizeShortId(raw);
    return id == null ? null : LiveMeLink(LiveMeLinkKind.shortId, id);
  }

  /// [raw] trimmed when it is a short id (5–12 digits, no leading zero),
  /// else null.
  static String? normalizeShortId(String raw) {
    final value = raw.trim();
    return _shortId.hasMatch(value) ? value : null;
  }

  /// [raw] trimmed when it is a user or video id (13–24 digits, no leading
  /// zero), else null.
  static String? normalizeLongId(String raw) {
    final value = raw.trim();
    return _longId.hasMatch(value) ? value : null;
  }

  /// The room page of [shortId], the room's link.
  static String url(String shortId) => '${LiveMeApi.origin}/livehot/streaming/$shortId';

  @override
  bool operator ==(Object other) => other is LiveMeLink && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'LiveMeLink(${kind.name}, $id)';
}

/// The request signature of LiveMe's official web client (3.x's
/// `LiveMeSigner`): the form gets the `lm_s_*` fields, and md5 over the
/// query and form pairs sorted by name (`name` + `value` each), the client
/// id, the timestamp and the web secret is the `lm-s-sign` header. The
/// constants ship in the web bundle; they identify the web client, not an
/// account.
final class LiveMeSigner {
  /// Creates a signer; [random] (the `vali` characters) is injectable for
  /// tests.
  new({math.Random? random}) : _random = random ?? math.Random.secure();

  /// `lm_s_id`.
  static const String clientId = 'LM6000101139961122666757';
  static const String _secret = 'dd46dbb442b6e4ba817d6347d2ddf493';
  static const String _valiAlphabet = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  final math.Random _random;
  var _counter = 0;

  /// [signAt] with the timestamp of [now]: its milliseconds and one counter
  /// digit, so two requests in one millisecond differ. (3.x's counter ran
  /// to 9999, so from the tenth request on the timestamp grew to 15–17
  /// digits instead of the web client's 14.)
  ({Map<String, String> fields, String signature}) sign({
    required Map<String, String> query,
    required Map<String, String> form,
    required DateTime now,
  }) {
    final timestamp = '${now.millisecondsSinceEpoch}$_counter';
    _counter = (_counter + 1) % 10;
    return signAt(query: query, form: form, timestamp: timestamp);
  }

  /// [form] with `lm_s_id`, `lm_s_ts` ([timestamp]), `lm_s_str` (its md5),
  /// `lm_s_ver` and `h5` added, and the `lm-s-sign` value over [query] and
  /// those fields.
  static ({Map<String, String> fields, String signature}) signAt({
    required Map<String, String> query,
    required Map<String, String> form,
    required String timestamp,
  }) {
    final fields = <String, String>{
      ...form,
      'lm_s_id': clientId,
      'lm_s_ts': timestamp,
      'lm_s_str': md5.convert(utf8.encode(timestamp)).toString(),
      'lm_s_ver': '1',
      'h5': '1',
    };
    final all = {...query, ...fields};
    final input = StringBuffer();
    for (final key in all.keys.toList()..sort()) {
      input
        ..write(key)
        ..write(all[key]);
    }
    input
      ..write(clientId)
      ..write(timestamp)
      ..write(_secret);
    return (fields: Map.unmodifiable(fields), signature: md5.convert(utf8.encode(input.toString())).toString());
  }

  /// The `vali` form value: 4 + `l` + 4 + `m` + 5 characters of the web
  /// client's alphabet.
  String vali() => '${_part(4)}l${_part(4)}m${_part(5)}';

  String _part(int length) =>
      List.generate(length, (_) => _valiAlphabet[_random.nextInt(_valiAlphabet.length)], growable: false).join();
}

/// What an answer says about a broadcast (3.x's `LiveMeState`, without its
/// `restricted`: a private or paid broadcast is live, 21-5).
enum LiveMeState {
  /// `online` 1, `status` 0 and `roomstate` 0.
  live,

  /// `online` 0, or another `status` or `roomstate`; or no current
  /// broadcast.
  offline,

  /// None of the above said anything.
  unknown,
}

/// The media URLs of one quality (21-7): FLV lines first, then HLS lines,
/// standing in for each other.
@immutable
final class LiveMeStream {
  /// Creates the stream.
  new({required this.qualityId, Iterable<String> flv = const [], Iterable<String> hls = const []})
    : flv = List.unmodifiable(flv),
      hls = List.unmodifiable(hls);

  /// [LiveMeApi.sourceQualityId] or [LiveMeApi.smoothQualityId].
  final String qualityId;

  /// FLV URLs, main field first, then the `*more` alternatives.
  final List<String> flv;

  /// HLS URLs.
  final List<String> hls;

  /// Every URL, in line order.
  List<String> get urls => [...flv, ...hls];
}

/// What one answer says about a room (3.x's `LiveMeRoom`): a featured card,
/// a search row, a broadcast (`queryinfosimple`), an anchor without one, or
/// a broadcast completed from the anchor's profile.
@immutable
final class LiveMeSnapshot {
  /// Creates the snapshot.
  new({
    required this.shortId,
    required this.userId,
    required this.nickname,
    required this.title,
    required this.state,
    this.videoId = '',
    this.avatar = '',
    this.cover = '',
    this.bio = '',
    this.countryCode = '',
    this.followers,
    this.currentViewers,
    this.totalViewers,
    this.heat,
    this.likes,
    this.startedAt,
    this.restriction,
    Iterable<LiveMeStream> streams = const [],
  }) : streams = List.unmodifiable(streams);

  /// The room id.
  final String shortId;

  /// The anchor's user id.
  final String userId;

  /// The broadcast (`vid`); empty when none.
  final String videoId;

  /// Anchor name.
  final String nickname;

  /// Title (the name when the broadcast has none, or only the app's
  /// default title).
  final String title;

  /// Avatar.
  final String avatar;

  /// Cover.
  final String cover;

  /// Introduction.
  final String bio;

  /// Two-letter country code, or empty.
  final String countryCode;

  /// Followers, when the answer says.
  final int? followers;

  /// `playnumber` of a live broadcast.
  final int? currentViewers;

  /// `watchnumber` of a live broadcast.
  final int? totalViewers;

  /// `heat` of a live broadcast.
  final int? heat;

  /// `likenum`.
  final int? likes;

  /// `vtime` of a live broadcast (UTC).
  final DateTime? startedAt;

  /// Of a live broadcast: private, paid or none; null when the answer does
  /// not say (a search row, an anchor without a broadcast).
  final LiveRestriction? restriction;

  /// Broadcast state.
  final LiveMeState state;

  /// Media of a live, unrestricted broadcast, when asked for.
  final List<LiveMeStream> streams;
}

/// An anchor's public profile (`user/getinfo`, 3.x's `_LiveMeProfile`).
@immutable
final class LiveMeProfile {
  /// Creates the profile.
  const new({
    required this.shortId,
    required this.userId,
    required this.nickname,
    this.avatar = '',
    this.cover = '',
    this.bio = '',
    this.countryCode = '',
    this.followers,
  });

  /// The anchor's short id.
  final String shortId;

  /// The anchor's user id.
  final String userId;

  /// Display name.
  final String nickname;

  /// `big_face`, else `face`.
  final String avatar;

  /// `big_cover`, else `cover`.
  final String cover;

  /// `usign`, the anchor's signature.
  final String bio;

  /// Two-letter country code, or empty.
  final String countryCode;

  /// `count_info.follower_count`.
  final int? followers;
}

/// What room entry learnt about a room's current broadcast; never stored
/// (3.x kept its `LiveMeRoom` in `data`).
@immutable
final class LiveMeRoomData {
  /// Creates the data.
  new({
    required this.shortId,
    required this.userId,
    required this.state,
    this.videoId = '',
    this.restriction,
    Iterable<LiveMeStream> streams = const [],
  }) : streams = List.unmodifiable(streams);

  /// The room id.
  final String shortId;

  /// The anchor's user id.
  final String userId;

  /// The current broadcast; empty when none. It is also the broadcast's
  /// chat room (`TCRoomId`), for M5.
  final String videoId;

  /// Its state.
  final LiveMeState state;

  /// Its restriction, when live.
  final LiveRestriction? restriction;

  /// Its media, [LiveMeApi.qualityNames] in order.
  final List<LiveMeStream> streams;
}

/// Pure parsing of LiveMe responses (3.x's `LiveMeApi`). Each function
/// takes the response text and status and returns 3.x's models or throws a
/// `SiteError`.
///
/// A room is an anchor's short id (`ushortid`, `short_id`); the user id and
/// the broadcast's video id are only used for requests. Room answers are
/// checked strictly, as in 3.x: an id that does not match what was asked, a
/// text field that is not text or a negative count is `ApiChanged`, never a
/// room. In lists and search a malformed row only drops itself (M4.U).
abstract final class LiveMeApi {
  /// The website.
  static const String origin = 'https://www.liveme.com';

  /// Host of the guest, search and broadcast APIs.
  static const String apiHost = 'live.liveme.com';

  /// Host of the featured list.
  static const String directoryHost = 'lvapi.liveme.com';

  /// The browser 3.x claimed to be, to the API and the media.
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  /// Largest answer 3.x accepted (8 MiB).
  static const int responseLimit = 8 * 1024 * 1024;

  /// Rows of a featured page (3.x's directory pager).
  static const int pageSize = 20;

  /// The note on every LiveMe room: 3.x's `liveme_chat_notice` ("LiveMe
  /// 远端聊天尚待接入；热度、当前观看和累计观看分别展示。") said for viewers
  /// (the unified rule on developer-style text); the interface may show its
  /// own translation (M13).
  static const String chatNotice = '这里暂时看不到 LiveMe 直播间的聊天。人数分别是热度、正在观看和累计观看。';

  /// The source quality (21-7): the broadcast's own stream, FLV lines
  /// (`videosource`, then `videosourcemore`) and the HLS line
  /// (`hlsvideosource`).
  static const String sourceQualityId = 'source';

  /// The 360p quality (21-7): FLV lines (`smallsource`, then
  /// `smallsourcemore`).
  static const String smoothQualityId = 'smooth';

  /// The qualities by id: the name and the sort value, best first.
  static const Map<String, ({String name, int sort})> qualityNames = {
    sourceQualityId: (name: '原画', sort: 300),
    smoothQualityId: (name: '流畅', sort: 200),
  };

  /// 3.x's quality ids (`原始画质 · FLV`, `HLS 自动 · HLS`,
  /// `流畅画质 · FLV`) → the quality that now holds their URLs as lines
  /// (21-7), for M9 to migrate a stored quality once. The old id's transport
  /// is the line's `lineId` (`flv`, `hls`).
  static const Map<String, String> legacyQualityIds = {
    'source-flv': sourceQualityId,
    'hls': sourceQualityId,
    'smooth-flv': smoothQualityId,
  };

  /// The quality id for [id] as stored before 21-7 ([legacyQualityIds],
  /// case-insensitive); any other id is kept.
  static String qualityIdFromLegacy(String id) => legacyQualityIds[id.trim().toLowerCase()] ?? id.trim();

  /// The app's default broadcast titles, one per interface language seen
  /// (2026-09-28: 129 of 199 cards on ten featured pages; the Arabic one on
  /// the Egyptian and Lebanese lists): a broadcast whose title is one of
  /// them has no title of its own, and is named as 3.x named an untitled
  /// one, by the anchor's name (the placeholder rule).
  static const Set<String> defaultTitles = {
    'Click for fun!',
    '¡Haz clic para divertirte!',
    'Clique e divirta-se!',
    'Нажмите и веселитесь!',
    'انقر للمتعة!',
  };

  /// The query of the signed `queryinfosimple` POST.
  static const Map<String, String> videoQuery = {'alias': 'liveme', 'tongdun_black_box': '1', 'os': 'web'};

  static final RegExp _country = RegExp(r'^[A-Z]{2}$');
  static final RegExp _unsafeMedia = RegExp(r'[\s\x00-\x1f]');

  /// Headers of every API request (3.x's `requestHeaders`): the referer is
  /// the room page of [shortId], else the hot list.
  static Map<String, String> headers({String? shortId}) => {
    'user-agent': userAgent,
    'accept': 'application/json, text/plain, */*',
    'accept-language': 'en-US,en;q=0.9',
    'origin': origin,
    'referer': shortId == null ? '$origin/livehot' : LiveMeLink.url(shortId),
  };

  /// Headers of the media of room [shortId] (3.x's `mediaHeaders`, which its
  /// `PlaybackHeaderResolver` gave the player and the recorder).
  static Map<String, String> mediaHeaders(String shortId) => {
    'user-agent': userAgent,
    'origin': origin,
    'referer': LiveMeLink.url(shortId),
  };

  /// The guest parameters of the API GETs at [now] (3.x's `_guestQuery`).
  static Map<String, String> guestQuery(DateTime now) => {
    'alias': 'liveme',
    'tongdun_black_box': '1',
    'os': 'web',
    '_time': '${now.millisecondsSinceEpoch}',
    'h5': '1',
    'thirdchannel': '6',
  };

  // Envelopes -----------------------------------------------------------------

  /// Maps an HTTP status other than 200 as 3.x did (it read no body then):
  /// 400 `ApiChanged`, 401 and 403 `RiskControl`, 404 `NotFound`, 420 and
  /// 429 `RateLimited`, anything else (5xx, a redirect) `NetworkFailure`.
  static void checkStatus(int status, String what) {
    switch (status) {
      case 200:
        return;
      case 400:
        throw ApiChanged(_site, '$what: HTTP 400');
      case 401 || 403:
        throw RiskControl(_site, detail: '$what: HTTP $status');
      case 404:
        throw NotFound(_site, '$what: HTTP 404');
      case 420 || 429:
        throw RateLimited(_site, detail: '$what: HTTP $status');
      default:
        throw NetworkFailure(_site, '$what: HTTP $status');
    }
  }

  /// The root object of an answer whose `status` (a string or a number) is
  /// 200. Other statuses as 3.x read them: 400 and 404 `NotFound` (an
  /// unknown short id is 400), 401 and 403 `RiskControl`, 420 and 429
  /// `RateLimited`, 500 "user not exist" `NotFound` (3.x: a service error),
  /// other 5xx `NetworkFailure`, anything else `ApiChanged`.
  static Map<String, dynamic> _envelope(String body, String what, int status) {
    checkStatus(status, what);
    if (body.length > responseLimit || (body.length * 3 > responseLimit && utf8.encode(body).length > responseLimit)) {
      throw ApiChanged(_site, '$what: answer over $responseLimit bytes');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ApiChanged(_site, '$what: not JSON');
    }
    final root = _object(decoded, what);
    final code = _integer(root['status']);
    final message = root['msg'] is String ? root['msg'] as String : '';
    return switch (code) {
      200 => root,
      null => throw ApiChanged(_site, '$what: no status'),
      400 || 404 => throw NotFound(_site, '$what: $code $message'),
      401 || 403 => throw RiskControl(_site, detail: '$what: $code $message'),
      420 || 429 => throw RateLimited(_site, detail: '$what: $code $message'),
      500 when message.contains('not exist') => throw NotFound(_site, '$what: $message'),
      final int other when other >= 500 => throw NetworkFailure(_site, '$what: $other $message'),
      final int other => throw ApiChanged(_site, '$what: status $other $message'),
    };
  }

  // Directory and search ------------------------------------------------------

  /// A `featurelist` page [page] (3.x's `directory`): the rooms, each once;
  /// another page when `next_page` is 1. A card without `ushortid` (a union
  /// room) is skipped. Private and paid broadcasts are listed as live and
  /// marked (21-1, 21-5; the discovery page hides them, M13). A malformed
  /// card only drops itself; a page whose cards are all malformed is
  /// `ApiChanged` (3.x failed the page on any).
  static LiveDirectoryPage featuredPage(String body, {required int page, int status = 200}) {
    final data = _object(_envelope(body, 'featurelist', status)['data'], 'featurelist.data');
    final rooms = <LiveRoom>[];
    final seen = <String>{};
    ApiChanged? broken;
    for (final row in _list(data['video_info'], 'featurelist.video_info', max: 100)) {
      final LiveMeSnapshot snapshot;
      try {
        final video = _object(row, 'featurelist row');
        if (video['ushortid'] == null) continue;
        snapshot = videoSnapshot(video);
      } on ApiChanged catch (error) {
        broken = error;
        continue;
      }
      if (seen.add(snapshot.shortId)) rooms.add(room(snapshot));
    }
    if (rooms.isEmpty && broken != null) throw broken;
    return LiveDirectoryPage(rooms: rooms, page: page, hasMore: _integer(data['next_page']) == 1);
  }

  /// A `searchKeyword` page (3.x's `search`): the anchors, live or not, each
  /// once, named (also as the title) by `nickname`, else `uname`. Live when
  /// `is_live` is 1, offline when it is 0 (21-4: also for the union
  /// projects, which report 0 while live; room entry has the truth), else
  /// unknown. A malformed row only drops itself; a page whose rows are all
  /// malformed is `ApiChanged` (3.x failed the page on any).
  static List<LiveRoom> searchPage(String body, {int status = 200}) {
    final data = _object(_envelope(body, 'searchKeyword', status)['data'], 'searchKeyword.data');
    final rooms = <LiveRoom>[];
    final seen = <String>{};
    ApiChanged? broken;
    for (final raw in _list(data['data_info'], 'searchKeyword.data_info', max: 100)) {
      final LiveMeSnapshot snapshot;
      try {
        snapshot = _searchRow(_object(raw, 'searchKeyword row'));
      } on ApiChanged catch (error) {
        broken = error;
        continue;
      }
      if (seen.add(snapshot.shortId)) rooms.add(room(snapshot));
    }
    if (rooms.isEmpty && broken != null) throw broken;
    return rooms;
  }

  static LiveMeSnapshot _searchRow(Map<String, dynamic> row) {
    final nickname = _firstText([row['nickname'], row['uname']], 'searchKeyword nickname');
    return LiveMeSnapshot(
      shortId: _shortId(row['short_id'], 'searchKeyword short_id'),
      userId: _longId(row['user_id'], 'searchKeyword user_id'),
      nickname: nickname,
      title: nickname,
      avatar: image(row['face']),
      countryCode: _countryCode(row['countryCode']),
      followers: _count(row['fans_num'] ?? row['follower_count'], 'searchKeyword fans_num'),
      state: switch (_integer(row['is_live'])) {
        1 => LiveMeState.live,
        0 => LiveMeState.offline,
        _ => LiveMeState.unknown,
      },
    );
  }

  // Rooms ---------------------------------------------------------------------

  /// `uid_vid_by_short_id`: the anchor's user id and the current broadcast's
  /// video id (empty when not broadcasting). An unknown short id is
  /// business 400 (`NotFound`).
  static ({String userId, String videoId}) mapping(String body, {int status = 200}) {
    final data = _object(_envelope(body, 'uid_vid_by_short_id', status)['data'], 'uid_vid_by_short_id.data');
    final userId = _longId(data['uid'], 'uid_vid_by_short_id uid');
    final videoId = _text(data['vid'], 'uid_vid_by_short_id vid');
    return (userId: userId, videoId: videoId.isEmpty ? '' : _longId(videoId, 'uid_vid_by_short_id vid'));
  }

  /// `user/getinfo` of [userId] (3.x's `_profile`): the answer must be that
  /// anchor's. The avatar is `big_face`, else `face`, and the cover
  /// `big_cover`, else `cover`, also when the first is empty (21-2). An
  /// unknown anchor is business 500 "user not exist" (`NotFound`).
  static LiveMeProfile profile(String body, {required String userId, int status = 200}) {
    final data = _object(_envelope(body, 'getinfo', status)['data'], 'getinfo.data');
    final user = _object(data['user'], 'getinfo.user');
    final info = _object(user['user_info'], 'getinfo.user_info');
    final actual = _longId(info['uid'] ?? info['userid'] ?? info['cm_openid'], 'getinfo uid');
    if (actual != userId) throw ApiChanged(_site, 'getinfo: asked $userId, got $actual');
    final counts = _object(user['count_info'], 'getinfo.count_info');
    return LiveMeProfile(
      shortId: _shortId(info['short_id'], 'getinfo short_id'),
      userId: actual,
      nickname: _firstText([info['nickname'], info['uname']], 'getinfo nickname'),
      avatar: _firstImage([info['big_face'], info['face']]),
      cover: _firstImage([info['big_cover'], info['cover']]),
      bio: _text(info['usign'], 'getinfo usign'),
      countryCode: _countryCode(info['countryCode']),
      followers: _count(counts['follower_count'], 'getinfo follower_count'),
    );
  }

  /// `live/queryinfosimple` of [videoId] (3.x's `_video`): its
  /// `video_info`, completed by `user_info`, must be that broadcast and,
  /// when [shortId] is given, that room's. The media is read only with
  /// [media].
  static LiveMeSnapshot video(
    String body, {
    required String videoId,
    String? shortId,
    bool media = false,
    int status = 200,
  }) {
    final data = _object(_envelope(body, 'queryinfosimple', status)['data'], 'queryinfosimple.data');
    final user = data['user_info'] is Map
        ? _object(data['user_info'], 'queryinfosimple.user_info')
        : const <String, dynamic>{};
    return videoSnapshot(
      _object(data['video_info'], 'queryinfosimple.video_info'),
      user: user,
      shortId: shortId,
      videoId: videoId,
      media: media,
    );
  }

  /// A `video_info` object (3.x's `_videoRoom`), completed by [user]. The
  /// ids must be [shortId] and [videoId] when given. While live it carries
  /// the viewers, total, heat, the start (`vtime`) and the restriction
  /// ([restrictionOf]); the media only with [media] and without a
  /// restriction. The title is the name when the broadcast has none or only
  /// one of the app's [defaultTitles]. The cover is `videocapture`, else
  /// `smallcover`, and the avatar `uface`, else the user's `face` or
  /// `icon`, also when the first is empty (21-2). The introduction is the
  /// user's `usign` only: `user_info.desc` is the anchor's name (21-3).
  static LiveMeSnapshot videoSnapshot(
    Map<String, dynamic> video, {
    Map<String, dynamic> user = const {},
    String? shortId,
    String? videoId,
    bool media = false,
  }) {
    final actualShortId = _shortId(video['ushortid'] ?? user['short_id'], 'video ushortid');
    final userId = _longId(video['userid'] ?? user['userid'] ?? user['uid'], 'video userid');
    final rawVideoId = _text(video['vid'] ?? video['vdoid'], 'video vid');
    final actualVideoId = rawVideoId.isEmpty ? '' : _longId(rawVideoId, 'video vid');
    if ((shortId != null && actualShortId != shortId) || (videoId != null && actualVideoId != videoId)) {
      throw ApiChanged(_site, 'queryinfosimple: asked $shortId/$videoId, got $actualShortId/$actualVideoId');
    }
    final online = _integer(video['online']);
    final state = _integer(video['status']);
    final roomState = _integer(video['roomstate']);
    final liveState = online == 1 && state == 0 && roomState == 0
        ? LiveMeState.live
        : online == 0 || (state != null && state != 0) || (roomState != null && roomState != 0)
        ? LiveMeState.offline
        : LiveMeState.unknown;
    final live = liveState == LiveMeState.live;
    final restriction = live ? restrictionOf(video) : null;
    final nickname = _firstText([video['uname'], user['uname'], user['nickname']], 'video uname');
    final title = _text(video['title'], 'video title');
    return LiveMeSnapshot(
      shortId: actualShortId,
      userId: userId,
      videoId: actualVideoId,
      nickname: nickname,
      title: title.isEmpty || defaultTitles.contains(title) ? nickname : title,
      avatar: _firstImage([video['uface'], user['face'], user['icon']]),
      cover: _firstImage([video['videocapture'], video['smallcover']]),
      bio: _text(user['usign'], 'video usign'),
      countryCode: _countryCode(video['countryCode'] ?? video['country_code'] ?? user['countryCode']),
      currentViewers: live ? _count(video['playnumber'], 'video playnumber') : null,
      totalViewers: live ? _count(video['watchnumber'], 'video watchnumber') : null,
      heat: live ? _count(video['heat'], 'video heat') : null,
      likes: _count(video['likenum'], 'video likenum'),
      startedAt: live ? startedAt(video['vtime']) : null,
      restriction: restriction,
      state: liveState,
      streams: media && restriction == LiveRestriction.none ? streams(video) : const [],
    );
  }

  /// The restriction of a `video_info` object, by the web client's own
  /// rule (its `hot_label_v2` is JSON text): `ispvt` 1 is private;
  /// `livebptype` 7 or the label text "Paid broadcast" (any case) is paid
  /// (21-1); anything else is none.
  static LiveRestriction restrictionOf(Map<String, dynamic> video) {
    if (_integer(video['ispvt']) == 1) return LiveRestriction.private;
    if (_integer(video['livebptype']) == 7 || isPaidLabel(video['hot_label_v2'])) return LiveRestriction.paid;
    return LiveRestriction.none;
  }

  /// Whether [label] (`hot_label_v2`: JSON text, as the site sends it, or an
  /// object, as 3.x read it) says "Paid broadcast". A label that does not
  /// parse says nothing (the web client reads it as `{}`).
  static bool isPaidLabel(Object? label) {
    var value = label;
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty || text.length > 65536) return false;
      try {
        value = jsonDecode(text);
      } on FormatException {
        return false;
      }
    }
    return value is Map && '${value['text'] ?? ''}'.trim().toLowerCase() == 'paid broadcast';
  }

  /// The start of a broadcast from its `vtime` (Unix seconds, the time the
  /// answer gives less `videolength`); null unless positive whole seconds
  /// of at most ten digits.
  static DateTime? startedAt(Object? value) {
    final seconds = value is int ? value : (value is String ? int.tryParse(value.trim()) : null);
    if (seconds == null || seconds <= 0 || seconds > 9999999999) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  /// An anchor without a current broadcast (3.x's `_offlineRoom`): offline,
  /// the name as the title, the profile's cover.
  static LiveMeSnapshot offline(LiveMeProfile profile) => LiveMeSnapshot(
    shortId: profile.shortId,
    userId: profile.userId,
    nickname: profile.nickname,
    title: profile.nickname,
    avatar: profile.avatar,
    cover: profile.cover,
    bio: profile.bio,
    countryCode: profile.countryCode,
    followers: profile.followers,
    state: LiveMeState.offline,
  );

  /// A broadcast completed by its anchor's profile (3.x's `_mergeProfile`):
  /// avatar, cover and country where the broadcast has none, the followers,
  /// and the anchor's signature as the introduction (21-3; the broadcast's
  /// own only when the profile has none).
  static LiveMeSnapshot withProfile(LiveMeSnapshot video, LiveMeProfile profile) => LiveMeSnapshot(
    shortId: video.shortId,
    userId: video.userId,
    videoId: video.videoId,
    nickname: video.nickname,
    title: video.title,
    avatar: video.avatar.isEmpty ? profile.avatar : video.avatar,
    cover: video.cover.isEmpty ? profile.cover : video.cover,
    bio: profile.bio.isEmpty ? video.bio : profile.bio,
    countryCode: video.countryCode.isEmpty ? profile.countryCode : video.countryCode,
    followers: profile.followers,
    currentViewers: video.currentViewers,
    totalViewers: video.totalViewers,
    heat: video.heat,
    likes: video.likes,
    startedAt: video.startedAt,
    restriction: video.restriction,
    state: video.state,
    streams: video.streams,
  );

  /// The room of [snapshot] (3.x's `LiveMeSite._card`): the short id is the
  /// room id and the room page its link. The heat is the popularity (and
  /// the old `watching`) when live, else the audience is the concurrent
  /// viewers; every room carries [chatNotice]. A restricted broadcast
  /// is live and marked (21-5; 3.x: banned). [data] is kept for streams.
  static LiveRoom room(LiveMeSnapshot snapshot, {LiveMeRoomData? data}) {
    final heat = snapshot.heat?.toString();
    return LiveRoom(
      roomId: snapshot.shortId,
      platform: _site,
      userId: snapshot.userId,
      link: LiveMeLink.url(snapshot.shortId),
      title: snapshot.title,
      nick: snapshot.nickname,
      avatar: snapshot.avatar,
      cover: snapshot.cover,
      area: snapshot.countryCode,
      watching: heat ?? '',
      popularity: heat ?? '',
      onlineViewers: snapshot.currentViewers?.toString() ?? '',
      totalViewers: snapshot.totalViewers?.toString() ?? '',
      audienceMetricType: heat == null ? AudienceMetricType.onlineViewers : AudienceMetricType.popularity,
      followers: snapshot.followers?.toString() ?? '',
      introduction: snapshot.bio,
      notice: chatNotice,
      liveStatus: switch (snapshot.state) {
        LiveMeState.live => LiveStatus.live,
        LiveMeState.offline => LiveStatus.offline,
        LiveMeState.unknown => LiveStatus.unknown,
      },
      startedAt: snapshot.startedAt,
      restriction: snapshot.restriction,
      data: data,
    );
  }

  /// The stream data of [snapshot].
  static LiveMeRoomData roomData(LiveMeSnapshot snapshot) => LiveMeRoomData(
    shortId: snapshot.shortId,
    userId: snapshot.userId,
    videoId: snapshot.videoId,
    state: snapshot.state,
    restriction: snapshot.restriction,
    streams: snapshot.streams,
  );

  // Streams -------------------------------------------------------------------

  /// The media of a live `video_info` (21-7): [sourceQualityId] with the FLV
  /// URLs of `videosource` and `videosourcemore` and the HLS URL of
  /// `hlsvideosource`; [smoothQualityId] with the FLV URLs of `smallsource`
  /// and `smallsourcemore`. Each [mediaUrl] once; a quality without one is
  /// left out. A field may be a URL, JSON text or a list or object of them.
  static List<LiveMeStream> streams(Map<String, dynamic> video) {
    List<String> urls(List<String> fields, StreamFormat format) => <String>{
      for (final field in fields)
        for (final raw in _flattenUrls(video[field])) ?mediaUrl(raw, format),
    }.toList();
    final source = LiveMeStream(
      qualityId: sourceQualityId,
      flv: urls(['videosource', 'videosourcemore'], StreamFormat.flv),
      hls: urls(['hlsvideosource'], StreamFormat.hls),
    );
    final smooth = LiveMeStream(
      qualityId: smoothQualityId,
      flv: urls(['smallsource', 'smallsourcemore'], StreamFormat.flv),
    );
    return [
      for (final stream in [source, smooth])
        if (stream.urls.isNotEmpty) stream,
    ];
  }

  /// Why room [shortId] with [restriction] is not played (the unified
  /// rule's `StreamUnavailable` with its reason), or null without one.
  static StreamUnavailable? restricted(String shortId, LiveRestriction? restriction) => switch (restriction) {
    null || LiveRestriction.none => null,
    final kind => StreamUnavailable(_site, '$shortId is restricted (${kind.name})'),
  };

  /// The qualities of the broadcast [data] holds (21-7): `原画`, `流畅`,
  /// those it has, best first. A private or paid broadcast (naming it), one
  /// that is not live, or a live one without media is `StreamUnavailable`.
  static List<LivePlayQuality> qualities(LiveMeRoomData data) {
    if (restricted(data.shortId, data.restriction) case final error?) throw error;
    if (data.state != LiveMeState.live) throw StreamUnavailable(_site, '${data.shortId} is ${data.state.name}');
    if (data.streams.isEmpty) throw StreamUnavailable(_site, '${data.shortId} has no media URL');
    return List.unmodifiable([
      for (final stream in data.streams)
        LivePlayQuality(
          quality: qualityNames[stream.qualityId]!.name,
          id: stream.qualityId,
          sort: qualityNames[stream.qualityId]!.sort,
        ),
    ]);
  }

  /// The lines of [quality] (by its id; one of 3.x's ids is read through
  /// [qualityIdFromLegacy]) of [data]'s broadcast, applied as the new id:
  /// FLV then HLS, each with the media headers and its format; the line id
  /// is the format (`flv`, `hls`), and the `*more` alternatives add `#2`,
  /// `#3` (the media hosts change with dispatch and name no line). No
  /// lease: the URLs' `wsABStime` is fixed for the broadcast and not
  /// enforced (21-8). A quality the broadcast does not offer is
  /// `StreamUnavailable`.
  static LivePlayUrlResolution resolution(LiveMeRoomData data, LivePlayQuality quality) {
    qualities(data);
    final wanted = qualityIdFromLegacy('${quality.selectionId}');
    final stream = data.streams.where((stream) => stream.qualityId == wanted).firstOrNull;
    if (stream == null) throw StreamUnavailable(_site, 'quality ${quality.selectionId} is not offered');
    return LivePlayUrlResolution.lines([
      for (final (format, urls) in [(StreamFormat.flv, stream.flv), (StreamFormat.hls, stream.hls)])
        for (final (index, url) in urls.indexed)
          LivePlayLine(
            url,
            headers: mediaHeaders(data.shortId),
            format: format,
            lineId: index == 0 ? format.name : '${format.name}#${index + 1}',
          ),
    ], appliedQualityData: wanted);
  }

  /// A media URL of [format]: http(s) with a host, without user info or
  /// fragment, with a `.flv` or `.m3u8` path. On 3.x's CDN hosts
  /// (`linkv.fun`, `emolm.com`, `liveme.com` or a subdomain, no explicit
  /// port) it is made https as 3.x did (the site's own web player forces
  /// https too); on any other host, which 3.x refused, it is kept as
  /// written (21-6). Null otherwise.
  static String? mediaUrl(String raw, StreamFormat format) {
    if (raw.isEmpty || raw.length > 65536 || _unsafeMedia.hasMatch(raw)) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !uri.path.toLowerCase().endsWith(format == StreamFormat.hls ? '.m3u8' : '.flv')) {
      return null;
    }
    if (!_mediaHost(uri.host.toLowerCase()) || uri.hasPort) return raw;
    return uri.replace(scheme: 'https').toString();
  }

  /// An image address as 3.x kept it (its `_image`), made absolute first
  /// (`normalizeImageUrl`): http(s) without user info or fragment on
  /// `esxscloud.com`, `liveme.com` or `linkv.fun` (or a subdomain), made
  /// https; else empty.
  static String image(Object? value) {
    if (value is! String || value.length > 8192) return '';
    final uri = Uri.tryParse(normalizeImageUrl(value));
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        !_imageHost(uri.host.toLowerCase())) {
      return '';
    }
    return uri.replace(scheme: 'https').toString();
  }

  /// The first of [values] that is an [image] (21-2: an empty or unusable
  /// field falls back to the next; 3.x fell back only when it was missing).
  static String _firstImage(List<Object?> values) {
    for (final value in values) {
      final url = image(value);
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  static bool _mediaHost(String host) => ['linkv.fun', 'emolm.com', 'liveme.com'].any((root) => _under(host, root));

  static bool _imageHost(String host) => ['esxscloud.com', 'liveme.com', 'linkv.fun'].any((root) => _under(host, root));

  static bool _under(String host, String root) => host == root || host.endsWith('.$root');

  /// 3.x's `_flattenUrls`: the http(s) strings in [value], reading JSON text
  /// (up to 128 KiB), lists and objects (up to 32 entries) three levels
  /// deep.
  static Iterable<String> _flattenUrls(Object? value, [int depth = 0]) sync* {
    if (depth > 3 || value == null) return;
    if (value is String) {
      final text = value.trim();
      if (text.startsWith('http://') || text.startsWith('https://')) {
        yield text;
        return;
      }
      if (text.length <= 131072 && (text.startsWith('[') || text.startsWith('{'))) {
        final Object? decoded;
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          return;
        }
        yield* _flattenUrls(decoded, depth + 1);
      }
      return;
    }
    if (value is List && value.length <= 32) {
      for (final item in value) {
        yield* _flattenUrls(item, depth + 1);
      }
      return;
    }
    if (value is Map && value.length <= 32) {
      for (final item in value.values) {
        yield* _flattenUrls(item, depth + 1);
      }
    }
  }

  // Helpers -------------------------------------------------------------------

  static Map<String, dynamic> _object(Object? value, String what) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, value) => MapEntry('$key', value));
    throw ApiChanged(_site, '$what: expected an object');
  }

  static List<Object?> _list(Object? value, String what, {required int max}) {
    if (value is! List || value.length > max) throw ApiChanged(_site, '$what: expected a list of at most $max');
    return value;
  }

  /// 3.x's `_integer`: an int, or a value whose text parses as one.
  static int? _integer(Object? value) => value is int ? value : int.tryParse(value?.toString() ?? '');

  /// 3.x's `_optionalNonNegativeInt`: null for null or '', else a count;
  /// anything else is `ApiChanged`.
  static int? _count(Object? value, String what) {
    if (value == null || value == '') return null;
    final number = _integer(value);
    if (number == null || number < 0) throw ApiChanged(_site, '$what: $value');
    return number;
  }

  /// 3.x's `_optionalText`: '' for null, else a string (at most 128 Ki
  /// characters) trimmed; anything else is `ApiChanged`.
  static String _text(Object? value, String what) {
    if (value == null) return '';
    if (value is! String || value.length > 131072) throw ApiChanged(_site, '$what: not text');
    return value.trim();
  }

  /// 3.x's `_firstText`: the first non-empty text of [values].
  static String _firstText(List<Object?> values, String what) {
    for (final value in values) {
      final text = _text(value, what);
      if (text.isNotEmpty) return text;
    }
    throw ApiChanged(_site, '$what: missing');
  }

  static String _shortId(Object? value, String what) =>
      LiveMeLink.normalizeShortId(value?.toString() ?? '') ?? (throw ApiChanged(_site, '$what: $value'));

  static String _longId(Object? value, String what) =>
      LiveMeLink.normalizeLongId(value?.toString() ?? '') ?? (throw ApiChanged(_site, '$what: $value'));

  /// 3.x's `_country`: two letters, upper case, else ''.
  static String _countryCode(Object? value) {
    final text = _text(value, 'countryCode').toUpperCase();
    return _country.hasMatch(text) ? text : '';
  }
}
