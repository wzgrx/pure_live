import 'dart:async';
import 'dart:math';

import 'package:live_core/src/json.dart';
import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_message.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/huya/huya_api.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

const _site = 'huya';
const _web = 'https://www.huya.com';
const _wupHost = 'wup.huya.com';

/// One token exchange as a whole (3.x: 6 s per phase, 8 s overall;
/// REG-HUYA-022).
const _tokenTimeout = Duration(seconds: 8);

/// The message board is auxiliary to playback (3.x: 2 s per phase, 3 s
/// overall).
const _boardTimeout = Duration(seconds: 3);

final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');
final RegExp _number = RegExp(r'^\d{1,19}$');
final RegExp _alias = RegExp(r'^[A-Za-z0-9_-]+$');

/// huya.com path segments that are pages, not room aliases (on top of
/// [RoomPaths.reservedSegments]).
const _pages = {'g', 'l', 'e', 'myfollow', 'download', 'play'};

/// What a room's streams need (3.x `HuyaUrlDataModel`): a live room's lines,
/// its qualities and the ids the room identity does not carry, or a replay's
/// recording.
@immutable
final class HuyaRoomData {
  /// Creates the data.
  new({
    required List<HuyaLine> lines,
    required List<LivePlayQuality> qualities,
    required this.presenterUid,
    required this.topSid,
    required this.subSid,
    this.replay,
    this.restriction,
  }) : lines = List.unmodifiable(lines),
       qualities = List.unmodifiable(qualities);

  /// Lines in server order: FLV, then HLS; none for a replay.
  final List<HuyaLine> lines;

  /// Qualities, the source first; a replay's is its recording's one
  /// quality until `getMomentContent` lists the others.
  final List<LivePlayQuality> qualities;

  /// Streamer uid.
  final int presenterUid;

  /// Top channel id (the message board's `lPid`).
  final int topSid;

  /// Sub channel id.
  final int subSid;

  /// The recording of a replay room (upgrade 3-1); null for a live room.
  final HuyaReplay? replay;

  /// The room's restriction; a paid or secret room is not played.
  final LiveRestriction? restriction;
}

typedef _Token = ({String token, int expireTime, DateTime receivedAt});

typedef _Opened = ({LivePlayLine? line, SiteError? error, bool expired});

/// The Huya adapter (3.x's `HuyaSite`; parsing and signing in [HuyaApi]).
///
/// Every line is signed on its own, in parallel: FLV with the native WUP
/// credential first, then the room's web template or a web WUP token; HLS
/// with its own AntiCode only. A line that cannot be signed is dropped
/// alone. Failures are `SiteError`s; nothing is disguised as an offline
/// room.
final class HuyaSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayUrlCursorResolver,
        LivePlayRecoveryResolver,
        LivePlayLeaseMetadata {
  /// Creates the adapter. [_cookies] holds the user's login cookie, if any.
  /// [playConfigUrls] are raced for the player configuration (3.x read it
  /// from the GitHub mirrors of the upstream repository). [preferH264]
  /// reads "优先 H.264" (on by default): on, every line asks for H.264 as
  /// 3.x did; off, FLV lines ask for HEVC (`codec=265`), which a room
  /// without an HEVC transcode answers with H.264. [now] and [random] are
  /// injectable for tests.
  new(
    this.http, {
    this._cookies,
    Iterable<Uri>? playConfigUrls,
    bool Function()? preferH264,
    DateTime Function()? now,
    Random? random,
  }) : playConfigUrls = List.unmodifiable(playConfigUrls ?? _playConfigMirrors),
       _preferH264 = preferH264 ?? _on,
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  static bool _on() => true;

  static final List<Uri> _playConfigMirrors = const GitHubMirror(
    owner: 'liuchuancong',
    repo: 'pure_live',
  ).mirrors('assets/play_config.json');

  /// Transport.
  final LiveHttp http;

  /// Where the player configuration (`assets/play_config.json`) is read.
  final List<Uri> playConfigUrls;

  final CookieVault? _cookies;
  final bool Function() _preferH264;
  final DateTime Function() _now;
  final Random _random;
  final HuyaSignClock _clock = HuyaSignClock();

  /// This instance's GUID for the web token's `tId`.
  late final String _guid = HuyaApi.guid(_random);

  /// The temporary viewer uid while anonymous login fails; never cached as
  /// the official identity (REG-HUYA-017).
  late final int _fallbackUid = HuyaApi.fallbackViewerUid(_random);

  int? _anonymousUid;

  /// The anonymous login in flight (one key), shared by concurrent callers.
  final Map<String, Future<int?>> _anonymousLogins = {};
  final Map<String, Future<_Token>> _nativeTokens = {};
  final Map<String, Future<_Token>> _webTokens = {};
  String? _playUserAgent;
  Future<String>? _playUserAgentLoad;
  final Map<String, PlayLease> _leases = {};
  final Map<String, int> _topSids = {};

  int _nativeFallbacks = 0;
  int _degradedViewers = 0;

  /// FLV lines that fell back from the native credential to the web path
  /// (a diagnostic, not an error).
  int get nativeFallbacks => _nativeFallbacks;

  /// Signatures made with the temporary viewer uid because anonymous login
  /// failed (a diagnostic, not an error).
  int get degradedViewers => _degradedViewers;

  @override
  String get id => _site;

  @override
  String get name => '虎牙直播';

  String _login() => (_cookies?.cookieFor(_site) ?? '').replaceAll(_controlCharacters, '').trim();

  // Requests ------------------------------------------------------------------

  Future<LiveResponse> _send(LiveRequest request) async {
    try {
      return await http.send(request);
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
  }

  Future<LiveResponse> _get(Uri url, {Map<String, String> headers = const {}}) =>
      _send(LiveRequest(site: _site, url: url, headers: headers));

  // Catalog and search --------------------------------------------------------

  /// The four top-level categories with their areas, requested together;
  /// one failure fails the whole tree.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) =>
      Future.wait([for (final top in HuyaApi.topCategories) _category(top.id, top.name)]);

  Future<LiveCategory> _category(String id, String name) async {
    final response = await _get(
      Uri.https('live.cdn.huya.com', '/liveconfig/game/bussLive', {'bussType': id}),
      headers: const {'user-agent': HuyaApi.userAgent},
    );
    return LiveCategory(
      id: id,
      name: name,
      children: HuyaApi.areas(response.text, categoryId: id, categoryName: name, status: response.status),
    );
  }

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) =>
      _liveList(page, gameId: category.areaId);

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) => _liveList(page);

  /// `getLiveListByPage` (120 rooms a page); recommendations add Origin and
  /// Referer.
  Future<List<LiveRoom>> _liveList(int page, {String? gameId}) async {
    final number = page < 1 ? 1 : page;
    final cookie = _login();
    final response = await _get(
      Uri.https('www.huya.com', '/cache.php', {
        'm': 'LiveList',
        'do': 'getLiveListByPage',
        'tagAll': '0',
        'gameId': ?gameId,
        'page': '$number',
      }),
      headers: {
        'user-agent': HuyaApi.userAgent,
        if (cookie.isNotEmpty) 'cookie': cookie,
        if (gameId == null) ...{'origin': _web, 'referer': '$_web/'},
      },
    );
    return HuyaApi.roomList(response.text, page: number, status: response.status).rooms;
  }

  /// Live rooms; [pageSize] is sent as `rows`, limited to 1–50. A blank
  /// keyword gives nothing without a request.
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final rows = pageSize.clamp(1, 50);
    final start = ((page < 1 ? 1 : page) - 1) * rows;
    final response = await _get(
      _searchUrl(text, version: 4, rows: rows, start: start),
      headers: _searchHeaders,
    );
    return HuyaApi.searchRooms(response.text, start: start, rows: rows, status: response.status);
  }

  /// Streamers, live or not.
  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async {
    final text = keyword.trim();
    if (text.isEmpty) return const [];
    final rows = pageSize < 1 ? 1 : pageSize;
    final response = await _get(
      _searchUrl(text, version: 1, rows: rows, start: ((page < 1 ? 1 : page) - 1) * rows),
      headers: _searchHeaders,
    );
    return HuyaApi.searchAnchors(response.text, status: response.status);
  }

  /// Search answers a request without a User-Agent with HTTP 403 `Not
  /// allowed` (2026-10-01); 3.x's Dio sent its own UA, this transport sends
  /// none unless asked.
  static const Map<String, String> _searchHeaders = {'user-agent': HuyaApi.userAgent};

  static Uri _searchUrl(String keyword, {required int version, required int rows, required int start}) =>
      Uri.https('search.cdn.huya.com', '/', {
        'm': 'Search',
        'do': 'getSearchContent',
        'q': keyword,
        'uid': '0',
        'v': '$version',
        'typ': '-5',
        'livestate': '0',
        'rows': '$rows',
        'start': '$start',
      });

  // Rooms ---------------------------------------------------------------------

  /// `profileRoom` past its ~30 s public cache: a millisecond `_` and
  /// no-cache headers (REG-HUYA-016). A room id that is not a number (a
  /// letter alias, which `profileRoom` refuses) is `NotFound` without a
  /// request.
  Future<HuyaProfile> _profile(String roomId) async {
    final id = roomId.trim();
    if (!_number.hasMatch(id)) throw NotFound(_site, 'room id $id is not a number');
    final cookie = _login();
    final response = await _get(
      Uri.https('mp.huya.com', '/cache.php', {
        'm': 'Live',
        'do': 'profileRoom',
        'roomid': id,
        'showSecret': '1',
        '_': '${_now().millisecondsSinceEpoch}',
      }),
      headers: {
        'accept': '*/*',
        'origin': _web,
        'referer': '$_web/',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-site',
        'user-agent': HuyaApi.userAgent,
        if (cookie.isNotEmpty) 'cookie': cookie,
        'cache-control': 'no-cache',
        'pragma': 'no-cache',
      },
    );
    final profile = HuyaApi.profile(response.text, requestedId: id, status: response.status);
    _topSids.remove(id);
    _topSids[id] = profile.topSid;
    if (_topSids.length > 512) _topSids.remove(_topSids.keys.first);
    return profile;
  }

  static HuyaRoomData _data(HuyaProfile profile) => HuyaRoomData(
    lines: profile.lines,
    qualities: profile.qualities,
    presenterUid: profile.presenterUid,
    topSid: profile.topSid,
    subSid: profile.subSid,
    replay: profile.replay,
    restriction: profile.room.restriction,
  );

  /// The room; a live one with its stream data and danmaku arguments, a
  /// replay with its recording (no danmaku). An offline room, or a replay
  /// without a recording, is returned as the platform describes it.
  Future<LiveRoom> _detail(String roomId) async {
    final profile = await _profile(roomId);
    if (profile.replay != null) return profile.room.copyWith(data: _data(profile));
    if (!profile.room.isLiveNow) return profile.room;
    final topSid = profile.topSid;
    return profile.room.copyWith(
      data: _data(profile),
      danmakuData: HuyaDanmakuArgs(
        uid: profile.presenterUid,
        topSid: topSid,
        subSid: profile.subSid,
        superChats: topSid > 0 ? () => messageBoard(topSid) : null,
      ),
    );
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  /// Follow-card refresh: metadata only.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) async => (await _profile(roomId)).room;

  /// The same detail as room entry (the recorder also records danmaku);
  /// failures are thrown, offline or replay only when the platform says so
  /// (neither is live, so neither is recorded).
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  @override
  Future<bool> getLiveStatus({required String roomId}) async => (await _profile(roomId)).room.isLiveNow;

  /// The room's headline message board. The top channel id comes from the
  /// room's last detail, or one `profileRoom` request.
  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) async {
    final id = roomId.trim();
    final topSid = _topSids[id] ?? (await _profile(id)).topSid;
    return topSid > 0 ? await messageBoard(topSid) : const [];
  }

  /// `wupui.getHeadLineMessageBoard` for [topSid]: every live entry.
  Future<List<LiveSuperChatMessage>> messageBoard(int topSid) async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https(_wupHost, '/'),
        method: 'POST',
        headers: const {
          'content-type': 'application/x-wup',
          'origin': _web,
          'referer': _web,
          'user-agent': HuyaApi.hysdkUserAgent,
        },
        body: HuyaApi.messageBoardRequest(topSid),
        timeout: _boardTimeout,
      ),
    );
    return HuyaApi.superChats(response.bytes, now: _now(), status: response.status);
  }

  // Streams -------------------------------------------------------------------

  /// The media User-Agent: `huya.user_agent` of the player configuration
  /// once [loadPlayUserAgent] read it, else the built-in HYSDK UA
  /// (REG-HUYA-024; an older HYSDK client than the built-in one is
  /// ignored, [HuyaApi.playUserAgent]).
  String get playUserAgent => _playUserAgent ?? HuyaApi.hysdkUserAgent;

  /// Races [playConfigUrls] once for the player configuration (3.x
  /// `getHuYaUA`, run at startup); an unreadable one keeps the built-in UA.
  /// Stream resolution never waits for it.
  Future<String> loadPlayUserAgent() => _playUserAgentLoad ??= () async {
    final config = await raceJson(http, _site, playConfigUrls);
    return _playUserAgent = HuyaApi.playUserAgent(config) ?? HuyaApi.hysdkUserAgent;
  }();

  /// The qualities of the room's stream data (requested again when the
  /// room has none). A replay's come from `getMomentContent` (one request
  /// when the replay is opened, upgrade 3-1); when that fails or lists
  /// nothing, the recording `profileRoom` named is the one quality.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    final data = await _roomData(detail);
    if (data.replay case final replay?) return await _replayQualities(replay, data.qualities);
    return data.qualities;
  }

  Future<List<LivePlayQuality>> _replayQualities(HuyaReplay replay, List<LivePlayQuality> fallback) async {
    final videoId = replay.videoId;
    if (videoId == null) return fallback;
    try {
      final response = await _get(
        Uri.https('liveapi.huya.com', '/moment/getMomentContent', {'videoId': '$videoId'}),
        headers: const {'user-agent': HuyaApi.userAgent, 'origin': _web, 'referer': '$_web/'},
      );
      final qualities = HuyaApi.replayQualities(response.text, status: response.status);
      return qualities.isEmpty ? fallback : qualities;
    } on SiteError {
      return fallback;
    }
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// Every line of the room's stream data at [quality], signed in parallel,
  /// in server order. Huya does not report the delivered quality, so the
  /// requested one counts as applied. When no line opens because the
  /// room's AntiCode expired, `profileRoom` is asked again once. A replay
  /// gives its recording's one line.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final data = await _roomData(detail);
    if (data.replay case final replay?) return _replayLines(detail.roomId, replay, quality);
    return await _resolve(detail.roomId, data, quality);
  }

  /// A fresh `profileRoom` and fresh signatures (a cached URL would reopen
  /// an expired source, REG-HUYA-025); the quality with the same id, else
  /// the best one. A replay quality's recording does not expire and is
  /// returned again without a request.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    if (HuyaApi.replayUrl(quality.data) case final url?) {
      return _replayLines(detail.roomId, HuyaReplay(url: url), quality);
    }
    final data = await _freshLiveData(detail.roomId);
    final requested = quality.selectionId.toString();
    final refreshed = data.qualities.firstWhere(
      (option) => option.selectionId.toString() == requested,
      orElse: () => data.qualities.first,
    );
    return await _resolve(detail.roomId, data, refreshed, fresh: true);
  }

  /// Signs only line [lineIndex] (recording asks for one line at a time);
  /// an index past the last line gives no URLs. A replay has one line.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlAtRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
    required int lineIndex,
  }) async {
    final data = await _roomData(detail);
    if (data.replay case final replay? when lineIndex == 0) return _replayLines(detail.roomId, replay, quality);
    if (lineIndex < 0 || lineIndex >= data.lines.length) {
      return LivePlayUrlResolution(urls: const [], appliedQualityData: quality.selectionId);
    }
    Future<int>? viewer;
    final opened = await _open(data.lines[lineIndex], _bitRate(quality), detail.roomId, () => viewer ??= _viewerUid());
    if (opened.line case final line?) {
      return LivePlayUrlResolution.lines([line], appliedQualityData: quality.selectionId);
    }
    throw opened.error!;
  }

  @override
  DateTime? getPlayUrlRefreshAt(String url, {DateTime? now}) {
    final lease = _leaseOf(url);
    if (lease == null) return null;
    final current = (now ?? _now()).toUtc();
    return lease.refreshAt.isAfter(current) ? lease.refreshAt : current;
  }

  @override
  DateTime? getPlayUrlInvalidAt(String url, {DateTime? now}) => _leaseOf(url)?.expiresAt;

  /// The lease a URL was issued with; one this adapter did not build is
  /// read from the URL itself.
  PlayLease? _leaseOf(String url) {
    if (_leases[url] case final lease?) return lease;
    final uri = Uri.tryParse(url);
    return uri == null ? null : HuyaApi.lease(uri);
  }

  void _rememberLease(String url, PlayLease? lease) {
    if (lease == null) return;
    _leases.remove(url);
    _leases[url] = lease;
    if (_leases.length > 64) _leases.remove(_leases.keys.first);
  }

  /// The room's stream data (requested again when the room has none), once
  /// it can be played.
  Future<HuyaRoomData> _roomData(LiveRoom detail) async => switch (detail.data) {
    final HuyaRoomData data => _playable(data),
    _ => await _freshData(detail.roomId),
  };

  /// A fresh `profileRoom`'s stream data: a live room, or a replay with a
  /// recording. Anything else has no playable stream right now, which is
  /// `StreamUnavailable`, not an error of the room.
  Future<HuyaRoomData> _freshData(String roomId) async {
    final profile = await _profile(roomId);
    final room = profile.room;
    if (!room.isLiveNow && profile.replay == null) {
      final unplayable = room.effectiveRestriction == LiveRestriction.unplayable ? ' without a recording' : '';
      throw StreamUnavailable(_site, 'profileRoom: the room is ${room.effectiveLiveStatus.name}$unplayable');
    }
    return _playable(_data(profile));
  }

  /// [_freshData] of a room that is still live: recovering or re-signing a
  /// live quality never switches to a replay's recording.
  Future<HuyaRoomData> _freshLiveData(String roomId) async {
    final data = await _freshData(roomId);
    if (data.replay != null) throw const StreamUnavailable(_site, 'profileRoom: the broadcast ended (replay)');
    return data;
  }

  /// [data] unless the room is restricted (M2.1): a paid room plays only
  /// for buyers and a secret room needs its password, so neither is opened;
  /// the error names the restriction.
  static HuyaRoomData _playable(HuyaRoomData data) => switch (data.restriction) {
    final LiveRestriction kind? when kind != LiveRestriction.none => throw StreamUnavailable(
      _site,
      'restricted room (${kind.name})',
    ),
    _ => data,
  };

  /// The recording's one line: [quality]'s playlist when it is a replay
  /// quality, else the one `profileRoom` named. No signature and no lease
  /// (the VOD URL does not expire); the media headers without the cookie.
  LivePlayUrlResolution _replayLines(String roomId, HuyaReplay replay, LivePlayQuality quality) {
    final requested = HuyaApi.replayUrl(quality.data);
    final url = requested ?? replay.url;
    return LivePlayUrlResolution.lines([
      LivePlayLine(
        url,
        headers: HuyaApi.mediaHeaders(roomId, userAgent: playUserAgent),
        format: StreamFormat.hls,
        lineId: 'replay|hls',
      ),
    ], appliedQualityData: requested != null ? quality.selectionId : HuyaApi.replayQuality(url).selectionId);
  }

  static int _bitRate(LivePlayQuality quality) => jsonInt(quality.data) ?? jsonInt(quality.id) ?? 0;

  Future<LivePlayUrlResolution> _resolve(
    String roomId,
    HuyaRoomData data,
    LivePlayQuality quality, {
    bool fresh = false,
  }) async {
    if (data.lines.isEmpty) throw const StreamUnavailable(_site, 'profileRoom: no multiLine entry with a stream');
    Future<int>? viewer;
    Future<int> viewerUid() => viewer ??= _viewerUid();
    final bitRate = _bitRate(quality);
    final results = await Future.wait([for (final line in data.lines) _open(line, bitRate, roomId, viewerUid)]);
    final seen = <String>{};
    final lines = [
      for (final result in results)
        if (result.line case final line? when seen.add(line.url)) line,
    ];
    if (lines.isNotEmpty) return LivePlayUrlResolution.lines(lines, appliedQualityData: quality.selectionId);
    if (!fresh && results.any((result) => result.expired)) {
      return await _resolve(roomId, await _freshLiveData(roomId), quality, fresh: true);
    }
    final errors = [for (final result in results) ?result.error];
    if (errors.isNotEmpty && errors.every((error) => error is NetworkFailure)) throw errors.first;
    throw errors.whereType<ApiChanged>().firstOrNull ??
        StreamUnavailable(_site, 'no line could be signed (${errors.map((error) => error.kind).toSet().join(', ')})');
  }

  /// One line signed, with its URL, headers and lease. Failures stay with
  /// the line (REG-HUYA-011); only cancellation escapes.
  Future<_Opened> _open(HuyaLine line, int bitRate, String roomId, Future<int> Function() viewer) async {
    try {
      final signed = await _sign(line, viewer);
      final url = HuyaApi.mediaUrl(line, antiCode: signed.antiCode, bitRate: bitRate, hevc: !_preferH264());
      final lease = HuyaApi.lease(url, builtAt: _now(), token: signed.window);
      final text = url.toString();
      _rememberLease(text, lease);
      return (
        line: LivePlayLine(
          text,
          headers: HuyaApi.mediaHeaders(roomId, userAgent: playUserAgent, cookie: _login()),
          format: line.format,
          codec: HuyaApi.codecOf(url),
          lineId: '${line.cdnType}|${line.format.name}|${HuyaApi.isNativeFlv(url) ? 'native' : 'web'}',
          lease: lease,
        ),
        error: null,
        expired: false,
      );
    } on HuyaSignException catch (failure) {
      final expired = failure.kind == HuyaSignFailure.expired;
      final detail = '$line: ${failure.reason}';
      return (
        line: null,
        error: expired ? StreamUnavailable(_site, detail) : ApiChanged(_site, detail),
        expired: expired,
      );
    } on SiteError catch (error) {
      return (line: null, error: error, expired: false);
    }
  }

  /// The signed query of [line] (3.x `getPlayUrl`):
  ///
  /// 1. FLV: the native credential for the stream name, whatever the room
  ///    token looks like (REG-HUYA-003), signed as the streamer (the viewer
  ///    when the line has no streamer uid).
  /// 2. Else a room token without `fm` is a legacy static token used as
  ///    is; a template is signed as the viewer; when that fails, a web
  ///    token for this viewer and line is fetched.
  /// 3. HLS uses only its own AntiCode, signed as the viewer
  ///    (REG-HUYA-006); the web path never uses the native identity
  ///    (REG-HUYA-009).
  Future<({String antiCode, HuyaTokenWindow? window})> _sign(HuyaLine line, Future<int> Function() viewer) async {
    final room = line.antiCode.trim();
    var antiCode = room;
    HuyaTokenWindow? window;
    var signed = false;
    if (line.format == StreamFormat.flv) {
      try {
        final token = await _nativeToken(line.streamName);
        final native = HuyaApi.tokenWindow(token.token, expireTime: token.expireTime, receivedAt: token.receivedAt);
        if (!_now().toUtc().isBefore(native.invalidAt)) {
          throw const StreamUnavailable(_site, 'getCdnTokenInfoEx: the native token arrived expired');
        }
        antiCode = _signWith(token.token, line, line.presenterUid > 0 ? line.presenterUid : await viewer());
        window = native;
        signed = true;
      } on HuyaSignException {
        _nativeFallbacks++;
      } on SiteError {
        _nativeFallbacks++;
      }
      if (!signed && HuyaApi.hasTemplate(room)) {
        final uid = await viewer();
        try {
          antiCode = _signWith(room, line, uid);
          signed = true;
        } on HuyaSignException catch (failure) {
          // 3.x signed the same room template again when the web token
          // failed, which failed the line the same way; the line fails with
          // the root cause instead: an expired template (so a fresh
          // profileRoom is worth it), else the token's error.
          try {
            final token = await _webToken(line, uid);
            window = HuyaApi.tokenWindow(token.token, expireTime: token.expireTime, receivedAt: token.receivedAt);
            antiCode = token.token;
          } on SiteError {
            if (failure.kind == HuyaSignFailure.expired) throw failure;
            rethrow;
          }
        }
      }
    }
    if (antiCode.isEmpty) throw StreamUnavailable(_site, '$line: no token');
    if (!signed && HuyaApi.hasTemplate(antiCode)) antiCode = _signWith(antiCode, line, await viewer());
    return (antiCode: antiCode, window: window);
  }

  String _signWith(String antiCode, HuyaLine line, int uid) => HuyaApi.signAntiCode(
    antiCode,
    streamName: line.streamName,
    uid: uid > 0 ? uid : _fallbackUid,
    clock: _clock,
    now: _now(),
    random: _random,
  );

  /// The native credential: `getCdnTokenInfoEx` with the `pc_exe` identity,
  /// no cookie and no viewer uid. One request per stream name at a time;
  /// nothing is cached, every caller signs its own URL.
  Future<_Token> _nativeToken(String streamName) => _shared(
    _nativeTokens,
    streamName,
    () => _fetchToken(
      flvUrl: '',
      streamName: streamName,
      userId: const HuyaUserId(huyaUa: HuyaApi.nativeTarsUserAgent),
      headers: const {'origin': _web, 'referer': '$_web/', 'user-agent': HuyaApi.hysdkUserAgent},
    ),
  );

  /// The web token for viewer [uid] and [line], with the login cookie; only
  /// the same viewer, line and stream share a request.
  Future<_Token> _webToken(HuyaLine line, int uid) {
    final cookie = _login();
    return _shared(
      _webTokens,
      '$uid|${line.base}|${line.streamName}',
      () => _fetchToken(
        flvUrl: line.base,
        streamName: line.streamName,
        userId: HuyaUserId(uid: uid, guid: _guid, huyaUa: HuyaApi.webTarsUserAgent, cookie: cookie),
        headers: {
          'origin': _web,
          'referer': '$_web/',
          'user-agent': HuyaApi.userAgent,
          if (cookie.isNotEmpty) 'cookie': cookie,
        },
      ),
    );
  }

  /// [fetch] shared by the callers of [key] while it runs; forgotten once
  /// it settles, so nothing is cached.
  static Future<T> _shared<T>(Map<String, Future<T>> inFlight, String key, Future<T> Function() fetch) async {
    if (inFlight[key] case final pending?) return await pending;
    final request = fetch();
    inFlight[key] = request;
    try {
      return await request;
    } finally {
      inFlight.removeWhere((pendingKey, pending) => pendingKey == key && identical(pending, request));
    }
  }

  /// `POST https://wup.huya.com` `liveui.getCdnTokenInfoEx`; a non-zero
  /// return code is `StreamUnavailable`.
  Future<_Token> _fetchToken({
    required String flvUrl,
    required String streamName,
    required HuyaUserId userId,
    required Map<String, String> headers,
  }) async {
    final response = await _send(
      LiveRequest(
        site: _site,
        url: Uri.https(_wupHost, '/'),
        method: 'POST',
        headers: {...headers, 'content-type': 'application/x-wup'},
        body: HuyaApi.cdnTokenRequest(flvUrl: flvUrl, streamName: streamName, userId: userId),
        timeout: _tokenTimeout,
      ),
    );
    final result = HuyaApi.cdnTokenResponse(response.bytes, status: response.status);
    if (result.code != 0) throw StreamUnavailable(_site, 'getCdnTokenInfoEx code ${result.code}');
    return (token: result.token, expireTime: result.expireTime, receivedAt: _now());
  }

  /// The viewer uid of web signatures: the cookie's `yyuid`, else the cached
  /// anonymous uid, else one shared anonymous login; when that fails, the
  /// temporary uid, and the next open asks again.
  Future<int> _viewerUid() async {
    final account = HuyaApi.viewerUidFromCookie(_login());
    if (account != null) return account;
    if (_anonymousUid case final uid?) return uid;
    final uid = await _shared(_anonymousLogins, '', _requestAnonymousUid);
    if (uid != null) return _anonymousUid = uid;
    _degradedViewers++;
    return _fallbackUid;
  }

  Future<int?> _requestAnonymousUid() async {
    try {
      final response = await _send(
        LiveRequest.json(
          site: _site,
          url: Uri.https('udblgn.huya.com', '/web/anonymousLogin'),
          json: const {'appId': 5002, 'byPass': 3, 'context': '', 'version': '2.4', 'data': <String, Object?>{}},
          headers: const {
            'user-agent': HuyaApi.userAgent,
            'accept': '*/*',
            'origin': _web,
            'referer': '$_web/',
            'sec-fetch-dest': 'empty',
            'sec-fetch-mode': 'cors',
            'sec-fetch-site': 'same-site',
          },
        ),
      );
      return HuyaApi.anonymousUid(response.text, status: response.status);
    } on NetworkFailure {
      return null;
    }
  }

  // Links ---------------------------------------------------------------------

  /// A numbered room page on huya.com or any of its subdomains
  /// (`www.huya.com/660000`, `m.huya.com/660000`).
  @override
  String? roomIdFromUrl(String url) {
    final segment = _roomSegment(url);
    return segment != null && _number.hasMatch(segment) ? segment : null;
  }

  /// A room page named by a letter alias (`www.huya.com/lpl`).
  @override
  bool needsResolving(String url) {
    final segment = _roomSegment(url);
    return segment != null && !_number.hasMatch(segment);
  }

  /// Looks the alias up on its room page (`TT_ROOM_DATA.profileRoom`);
  /// `profileRoom` itself refuses aliases (3.x opened them and failed). A
  /// redirect is parsed again.
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final alias = _roomSegment(url);
    if (alias == null) return null;
    final page = Uri.https('www.huya.com', '/$alias');
    final response = await session.get(
      page,
      readBody: true,
      headers: const {'user-agent': HuyaApi.desktopUserAgent, 'accept': 'text/html,application/xhtml+xml'},
    );
    final target = ShortLinkSession.redirectTarget(page, response);
    if (target != null) return LinkRedirect(target);
    if (response == null || response.status != 200) return null;
    final id = HuyaApi.roomIdFromPage(response.text);
    return id == null ? null : LinkRoom(id);
  }

  /// The first path segment of a huya.com page when it can name a room
  /// (3.x `WebSearchRoomParser`: letters, digits, `_` and `-`).
  static String? _roomSegment(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !RoomPaths.hostIs(uri.host.toLowerCase(), 'huya.com')) return null;
    final segment = RoomPaths.firstSegment(uri, _alias);
    return segment == null || _pages.contains(segment.toLowerCase()) ? null : segment;
  }
}
