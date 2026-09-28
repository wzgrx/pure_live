import 'dart:async';
import 'dart:math' as math;

import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/liveme/liveme_api.dart';
import 'package:live_net/live_net.dart';

const _site = 'liveme';

/// The LiveMe adapter (3.x's `LiveMeSite`; parsing in [LiveMeApi]).
///
/// A room is an anchor's short id, as in 3.x, so 3.x's follows keep
/// matching; the user id and the current broadcast's video id live in
/// [LiveMeRoomData]. Anonymous, like 3.x: no cookie, no account; every
/// request carries [LiveMeApi.headers] and follows no redirect. Requests
/// are 3.x's:
/// - recommendations and the directory are `featurelist` pages;
/// - search is `searchKeyword`, or a room lookup for a short id or a link;
/// - a room (entry, refresh, recording, live status) is the short id's
///   `uid_vid_by_short_id`, then the anchor's `getinfo` and, while
///   broadcasting, the signed `queryinfosimple`, in parallel;
/// - fresh media (recovery, or a room without stream data) is
///   `uid_vid_by_short_id` and `queryinfosimple` only.
///
/// A private or paid broadcast is live and marked with its restriction; its
/// stream says why it is not played (M4.U). Failures are `SiteError`s;
/// nothing is disguised as an offline room.
final class LiveMeSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter; [now] (the `_time` and signature clock) and
  /// [random] (the signature's `vali`) are injectable for tests.
  new(this.http, {DateTime Function()? now, math.Random? random})
    : _now = now ?? DateTime.now,
      _signer = LiveMeSigner(random: random);

  /// Transport.
  final LiveHttp http;

  final DateTime Function() _now;
  final LiveMeSigner _signer;

  @override
  String get id => _site;

  @override
  String get name => 'LiveMe';

  /// 3.x's lasting note on what the directory and search cover.
  @override
  String get directoryNoticeKey => 'liveme_directory_scope';

  // Requests ------------------------------------------------------------------

  /// Sends [request] (redirects not followed, as 3.x). A cancellation before
  /// the request or while it runs is a cancelled `TransportFailure`, also
  /// when the answer (or a transport failure) arrived meanwhile; other
  /// transport failures are `NetworkFailure`.
  Future<LiveResponse> _send(LiveRequest request, {CancelToken? cancel}) async {
    try {
      _checkCancelled(cancel);
      final response = await http.send(request);
      _checkCancelled(cancel);
      return response;
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      _checkCancelled(cancel);
      throw NetworkFailure(_site, failure.toString());
    }
  }

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  Future<LiveResponse> _get(Uri url, {String? shortId, CancelToken? cancel}) => _send(
    LiveRequest(
      site: _site,
      url: url,
      headers: LiveMeApi.headers(shortId: shortId),
      followRedirects: false,
      cancel: cancel,
    ),
    cancel: cancel,
  );

  Uri _guest(String path, Map<String, String> query) =>
      Uri.https(LiveMeApi.apiHost, path, {...LiveMeApi.guestQuery(_now()), ...query});

  Uri _profileUrl(String userId) => _guest('/user/getinfo', {'userid': userId});

  /// The signed `queryinfosimple` POST of [videoId] (3.x's `_video`): the
  /// form and `lm-s-sign` of [LiveMeSigner], the referer of [shortId]'s
  /// room when known, 3.x's plain form content type.
  LiveRequest _videoRequest(String videoId, {String? shortId, CancelToken? cancel}) {
    final now = _now();
    final signed = _signer.sign(
      query: LiveMeApi.videoQuery,
      form: {
        '_time': '${now.millisecondsSinceEpoch}',
        'thirdchannel': '6',
        'videoid': videoId,
        'area': 'en',
        'vali': _signer.vali(),
      },
      now: now,
    );
    final url = Uri.https(LiveMeApi.apiHost, '/live/queryinfosimple', LiveMeApi.videoQuery);
    return LiveRequest(
      site: _site,
      url: url,
      method: 'POST',
      headers: {
        ...LiveMeApi.headers(shortId: shortId),
        'lm-s-sign': signed.signature,
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: LiveRequest.form(site: _site, url: url, fields: signed.fields).body,
      followRedirects: false,
      cancel: cancel,
    );
  }

  Future<({String userId, String videoId})> _mapping(String shortId, {CancelToken? cancel}) async {
    final response = await _get(
      _guest('/liveme_ent/v1/user/uid_vid_by_short_id', {'short_id': shortId}),
      shortId: shortId,
      cancel: cancel,
    );
    return LiveMeApi.mapping(response.text, status: response.status);
  }

  Future<LiveMeProfile> _profile(String userId, {CancelToken? cancel}) async {
    final response = await _get(_profileUrl(userId), cancel: cancel);
    return LiveMeApi.profile(response.text, userId: userId, status: response.status);
  }

  Future<LiveMeSnapshot> _video(String videoId, {String? shortId, bool media = false, CancelToken? cancel}) async {
    final response = await _send(
      _videoRequest(videoId, shortId: shortId, cancel: cancel),
      cancel: cancel,
    );
    return LiveMeApi.video(response.text, videoId: videoId, shortId: shortId, media: media, status: response.status);
  }

  // Directory -----------------------------------------------------------------

  /// Native page [page] of the featured list (20 rooms a page, as 3.x's
  /// pager asked). LiveMe has no categories: a [category] is a caller error
  /// (`ArgumentError`, no request), as 3.x refused it.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (category != null) throw ArgumentError.value(category, 'category', 'LiveMe has no categories');
    return await _featured(page: page, pageSize: LiveMeApi.pageSize, cancel: cancel);
  }

  /// The featured page [page] of [pageSize] rooms (sent, kept within 1–50).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async =>
      (await _featured(page: page, pageSize: pageSize.clamp(1, 50))).rooms;

  /// A page below 1 is a caller error (`ArgumentError`), refused before any
  /// request as in 3.x.
  Future<LiveDirectoryPage> _featured({required int page, required int pageSize, CancelToken? cancel}) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    final response = await _get(
      Uri.https(LiveMeApi.directoryHost, '/live/featurelist', {
        'countryCode': 'GLOBAL',
        'page_index': '$page',
        'page_size': '$pageSize',
        'pid': '3',
        'posid': '3002',
        'h5': '1',
      }),
      cancel: cancel,
    );
    return LiveMeApi.featuredPage(response.text, page: page, status: response.status);
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// Anchors for [keyword] (3.x's rules):
  /// - a short id (5–12 digits) or a room, anchor or share link finds that
  ///   room on page 1 only (its refresh detail; an anchor or share link
  ///   first asks for the short id); an unknown room finds nothing;
  /// - a blank keyword, a page or a [pageSize] below 1 finds nothing,
  ///   without a request;
  /// - anything else is a keyword of `searchKeyword`, [pageSize] sent
  ///   within 1–40 (the site answers 20 a page whatever is asked); a keyword
  ///   over 256 characters is refused (`ArgumentError`, no request), as 3.x
  ///   refused it.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final reference = LiveMeLink.parseOrShortId(keyword);
    if (reference != null) {
      if (page != 1) return const [];
      try {
        final shortId = await _shortIdOf(reference, cancel: cancel);
        return [await _room(shortId, media: false, cancel: cancel)];
      } on NotFound {
        return const [];
      }
    }
    final query = keyword.trim();
    if (query.isEmpty || page < 1 || pageSize < 1) return const [];
    if (query.length > 256) throw ArgumentError.value(keyword, 'keyword', 'over 256 characters');
    final response = await _get(
      _guest('/search/searchKeyword', {
        'type': '1',
        'page': '$page',
        'pageSize': '${pageSize.clamp(1, 40)}',
        'keyword': query,
        'tuid': '',
        'uid': '',
        'token': '',
        'androidid': '',
      }),
      cancel: cancel,
    );
    return LiveMeApi.searchPage(response.text, status: response.status);
  }

  /// The short id [link] names (3.x's `resolveReference`): as written, or
  /// asked of the anchor's profile or the broadcast.
  Future<String> _shortIdOf(LiveMeLink link, {CancelToken? cancel}) async => switch (link.kind) {
    LiveMeLinkKind.shortId => link.id,
    LiveMeLinkKind.userId => (await _profile(link.id, cancel: cancel)).shortId,
    LiveMeLinkKind.videoId => (await _video(link.id, cancel: cancel)).shortId,
  };

  // Rooms ---------------------------------------------------------------------

  /// Room [roomId] (3.x's `LiveMeApi.room`): the short id's user and
  /// broadcast, then the anchor's profile and, when broadcasting, the
  /// broadcast, in parallel; both must be this room's and this anchor's. A
  /// room id that is not a short id is `NotFound` without a request. With
  /// [media] the stream data comes along; a broadcast that cannot be played
  /// (private or paid, not live, no media) is still returned, a private or
  /// paid one live and marked, and its stream says why.
  Future<LiveRoom> _room(String roomId, {required bool media, CancelToken? cancel}) async {
    final shortId = LiveMeLink.normalizeShortId(roomId);
    if (shortId == null) throw NotFound(_site, 'not a short id: $roomId');
    final mapping = await _mapping(shortId, cancel: cancel);
    final profileAnswer = _profile(mapping.userId, cancel: cancel);
    final LiveMeSnapshot snapshot;
    final LiveMeProfile profile;
    if (mapping.videoId.isEmpty) {
      profile = await profileAnswer;
      snapshot = LiveMeApi.offline(profile);
    } else {
      final answers = await Future.wait<Object>([
        profileAnswer,
        _video(mapping.videoId, shortId: shortId, media: media, cancel: cancel),
      ]);
      profile = answers[0] as LiveMeProfile;
      final video = answers[1] as LiveMeSnapshot;
      if (video.userId != mapping.userId) throw ApiChanged(_site, 'queryinfosimple: not the anchor of $shortId');
      snapshot = LiveMeApi.withProfile(video, profile);
    }
    if (profile.shortId != shortId) throw ApiChanged(_site, 'getinfo: ${profile.shortId} for $shortId');
    return LiveMeApi.room(snapshot, data: media ? LiveMeApi.roomData(snapshot) : null);
  }

  /// The room with its stream data.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _room(roomId, media: true);

  /// Follow-card refresh: the same requests as room entry (as in 3.x),
  /// without the stream data.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _room(roomId, media: false);

  /// Room entry's answer (the stream data included), as 3.x's recorder
  /// asked.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _room(roomId, media: true);

  /// Whether the refresh detail says live. A failed request, or an answer
  /// that says nothing about the state, is an error, never "offline"
  /// (3.x's `unknownState`).
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final room = await getRoomDetailForRefresh(roomId: roomId);
    if (room.isLiveStatusPending) throw ApiChanged(_site, '$roomId: the broadcast state is not given');
    return room.isLiveNow;
  }

  // Streams -------------------------------------------------------------------

  /// The qualities (see [LiveMeApi.qualities]) from the stream data room
  /// entry brought: no request. A room without it (a list card, a refreshed
  /// follow) asks for the current broadcast first; one the platform called
  /// offline or banned, or marked private or paid, has no stream
  /// (`StreamUnavailable`, without a request).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      LiveMeApi.qualities(await _stream(detail, fresh: false));

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The lines of [quality] with the media headers; 3.x's quality ids are
  /// read as the new ones ([LiveMeApi.qualityIdFromLegacy]).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LiveMeApi.resolution(await _stream(detail, fresh: false), quality);

  /// The current broadcast asked for again: the anchor may have started a
  /// new one, and the URLs are signed. A quality the broadcast lacks, or no
  /// broadcast, is `StreamUnavailable`; the old URLs are never reused.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LiveMeApi.resolution(await _stream(detail, fresh: true), quality);

  Future<LiveMeRoomData> _stream(LiveRoom detail, {required bool fresh}) async {
    if (!fresh) {
      if (detail.data case final LiveMeRoomData data when data.shortId == detail.roomId) return data;
      if (detail.isExplicitlyOfflineNow) {
        throw StreamUnavailable(_site, '${detail.roomId} is ${detail.effectiveLiveStatus.name}');
      }
      if (LiveMeApi.restricted(detail.roomId, detail.restriction) case final error?) throw error;
    }
    return await _media(detail.roomId);
  }

  /// The stream data of room [roomId]'s current broadcast: the short id's
  /// user and broadcast, then the broadcast (two requests; the profile adds
  /// nothing to a stream). No broadcast is `StreamUnavailable`.
  Future<LiveMeRoomData> _media(String roomId) async {
    final shortId = LiveMeLink.normalizeShortId(roomId);
    if (shortId == null) throw NotFound(_site, 'not a short id: $roomId');
    final mapping = await _mapping(shortId);
    if (mapping.videoId.isEmpty) throw StreamUnavailable(_site, '$shortId is not broadcasting');
    final video = await _video(mapping.videoId, shortId: shortId, media: true);
    if (video.userId != mapping.userId) throw ApiChanged(_site, 'queryinfosimple: not the anchor of $shortId');
    return LiveMeApi.roomData(video);
  }

  // Links ---------------------------------------------------------------------

  /// A room page (`liveme.com/[locale/]livehot/streaming/<short id>`),
  /// without a request (see [LiveMeLink.parse]).
  @override
  String? roomIdFromUrl(String url) {
    final link = LiveMeLink.parse(url);
    return link?.kind == LiveMeLinkKind.shortId ? link!.id : null;
  }

  /// An anchor page (`/u/<uid>`) or a broadcast's share page (`/v/<vid>`,
  /// `/m/v/<vid>/index.html`): its short id needs a request.
  @override
  bool needsResolving(String url) {
    final kind = LiveMeLink.parse(url)?.kind;
    return kind == LiveMeLinkKind.userId || kind == LiveMeLinkKind.videoId;
  }

  /// The short id of an anchor or share link through [session], one request
  /// as in 3.x's link import: the anchor's `getinfo`, or the broadcast's
  /// signed `queryinfosimple`. Null when it fails (3.x's import reported the
  /// error instead; its toolbox said "parse failed" either way).
  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final link = LiveMeLink.parse(url);
    try {
      switch (link?.kind) {
        case LiveMeLinkKind.userId:
          final response = await session.get(_profileUrl(link!.id), readBody: true, headers: LiveMeApi.headers());
          if (response == null) return null;
          return LinkRoom(LiveMeApi.profile(response.text, userId: link.id, status: response.status).shortId);
        case LiveMeLinkKind.videoId:
          final response = await session.send(_videoRequest(link!.id));
          if (response == null) return null;
          return LinkRoom(LiveMeApi.video(response.text, videoId: link.id, status: response.status).shortId);
        case LiveMeLinkKind.shortId || null:
          return null;
      }
    } on SiteError {
      return null;
    }
  }
}
