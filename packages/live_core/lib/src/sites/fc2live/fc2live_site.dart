import 'package:live_core/src/links.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/fc2live/fc2live_api.dart';
import 'package:live_core/src/sites/fc2live/fc2live_control.dart';
import 'package:live_net/live_net.dart';

const _site = 'fc2live';

/// Where the API answers.
const _host = 'live.fc2.com';

/// How long a snapshot fetched without a cancel token is reused (3.x).
const _snapshotLifetime = Duration(seconds: 20);

/// The FC2 Live adapter (3.x's `Fc2Site` and `Fc2Api`; parsing in
/// [Fc2LiveApi], the control socket in [Fc2LiveControl]).
///
/// Anonymous, like 3.x: no cookie, no account and no comments (3.x's FC2
/// had `EmptyDanmaku`). Every request is a form POST with 3.x's headers
/// that does not follow redirects and goes as `fc2live`, so the app routes
/// the platform through its proxy setting. The requests are 3.x's:
/// - the directory, the recommendations, the area rooms and the keyword
///   search are all the `allchannellist.php` snapshot of every channel on
///   air, paged locally. A snapshot asked for without a cancel token is
///   shared for 20 s (and while it is being fetched); one asked for with a
///   token (the directory and search pages always pass one) is fetched
///   anew, as in 3.x;
/// - a room is one `memberApi.php` request, at room entry, refresh,
///   recording and the live-status check alike; a search for a channel
///   number or link is that request too;
/// - streams have no URL: the one quality resolves to a
///   [Fc2LiveInputRecipe] that playback and recording open themselves with
///   [openControl] (M7, M8): `memberApi.php`, `getControlServer.php` and
///   the control socket, held while they play.
///
/// Rooms are identified by the channel number, as 3.x stored them.
/// Failures are `SiteError`s; nothing is disguised as an offline room.
final class Fc2LiveSite extends LiveSite
    with LiveSiteLinks
    implements
        LiveSiteDirectoryPager,
        LiveDirectoryNotice,
        LiveCancellableSearch,
        LiveSiteRoomRefresher,
        LiveSiteRecordRoomResolver,
        LivePlayUrlResolver,
        LivePlayRecoveryResolver {
  /// Creates the adapter. Control sockets connect with [connector] (default
  /// [Fc2LiveControl.connect]: `dart:io` with 3.x's 15 s ping) through
  /// [proxy]'s route for `fc2live`, the one the app gives [http] too.
  /// [controlStartupTimeout] bounds a control's handshake and HLS answer;
  /// [now] (the snapshot's age) is injectable for tests.
  new(
    this.http, {
    this.proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    this.controlStartupTimeout = const Duration(seconds: 20),
    DateTime Function()? now,
  }) : _connector = connector ?? Fc2LiveControl.connect,
       _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  /// Proxy routes of the control sockets.
  final ProxyPolicy proxy;

  /// Longest wait for a control's HLS answer (3.x: 20 s).
  final Duration controlStartupTimeout;

  final SocketConnector _connector;
  final DateTime Function() _now;
  Future<List<Fc2LiveChannel>>? _snapshot;
  DateTime? _snapshotAt;

  @override
  String get id => _site;

  @override
  String get name => 'FC2 Live';

  /// 3.x's text key for the directory's scope note (a snapshot of the live
  /// channels, filtered and searched locally; exact channels and links find
  /// offline ones too).
  @override
  String get directoryNoticeKey => 'fc2live_directory_scope';

  // Requests ------------------------------------------------------------------

  /// A form POST of [fields] to [path] with 3.x's headers, redirects not
  /// followed (as 3.x). A cancellation before the request or while it runs
  /// is a cancelled `TransportFailure`, also when the answer arrived
  /// meanwhile; other transport failures are `NetworkFailure`.
  Future<LiveResponse> _post(String path, Map<String, String> fields, {CancelToken? cancel}) async {
    _checkCancelled(cancel);
    final url = Uri.https(_host, path);
    final LiveResponse response;
    try {
      response = await http.send(
        LiveRequest(
          site: _site,
          url: url,
          method: 'POST',
          headers: const {...Fc2LiveApi.headers, 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8'},
          body: LiveRequest.form(site: _site, url: url, fields: fields).body,
          followRedirects: false,
          cancel: cancel,
        ),
      );
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      _checkCancelled(cancel);
      throw NetworkFailure(_site, failure.toString());
    }
    _checkCancelled(cancel);
    return response;
  }

  static void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw const TransportFailure(_site, TransportReason.cancelled);
  }

  // Snapshot ------------------------------------------------------------------

  Future<List<Fc2LiveChannel>> _fetchSnapshot({CancelToken? cancel}) async {
    final response = await _post('/contents/allchannellist.php', const {}, cancel: cancel);
    return Fc2LiveApi.directory(response.text, status: response.status);
  }

  /// The `allchannellist` snapshot. With [cancel] it is always fetched anew
  /// (3.x: a cancellable caller never shares a request). Without, the last
  /// one is reused for 20 s after it arrived, and a fetch under way is
  /// shared (3.x fetched again for every caller that came before the first
  /// answer); a failed fetch is forgotten.
  Future<List<Fc2LiveChannel>> _snapshotFor(CancelToken? cancel) {
    if (cancel != null) return _fetchSnapshot(cancel: cancel);
    final cached = _snapshot;
    final at = _snapshotAt;
    if (cached != null && (at == null || _now().difference(at) < _snapshotLifetime)) return cached;
    late final Future<List<Fc2LiveChannel>> fetch;
    fetch = _fetchSnapshot().then(
      (channels) {
        if (identical(_snapshot, fetch)) _snapshotAt = _now();
        return channels;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_snapshot, fetch)) {
          _snapshot = null;
          _snapshotAt = null;
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _snapshot = fetch;
    _snapshotAt = null;
    return fetch;
  }

  // Catalog and directory -----------------------------------------------------

  /// 3.x's one category `FC2 Live` with its six areas; other pages (and a
  /// page size below 1) are empty. No request.
  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async {
    if (page != 1 || pageSize < 1) return const [];
    return [Fc2LiveApi.category()];
  }

  /// Page [page] (20 rooms) of [category]'s channels, or of every channel
  /// when it is null or `all` (3.x). A page below 1 or an area that is not
  /// one of this platform's is a caller error, without a request.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    final filter = category == null ? null : Fc2LiveApi.areaFilter(category);
    _checkCancelled(cancel);
    final channels = await _snapshotFor(cancel);
    return Fc2LiveApi.directoryPage([
      for (final channel in channels)
        if (Fc2LiveApi.inArea(channel, filter)) channel,
    ], page: page);
  }

  /// Slice [page] of [pageSize] of every channel (3.x's `_page`: a page or
  /// size below 1, or a size over 100, gives nothing, now without a
  /// request).
  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (!Fc2LiveApi.validSlice(page: page, pageSize: pageSize)) return const [];
    final channels = await _snapshotFor(null);
    return [for (final channel in Fc2LiveApi.slice(channels, page: page, pageSize: pageSize)) Fc2LiveApi.room(channel)];
  }

  /// As [getRecommendRooms], for the area [category] (an area that is not
  /// one of this platform's is a caller error, without a request).
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final filter = Fc2LiveApi.areaFilter(category);
    if (!Fc2LiveApi.validSlice(page: page, pageSize: pageSize)) return const [];
    final channels = [
      for (final channel in await _snapshotFor(null))
        if (Fc2LiveApi.inArea(channel, filter)) channel,
    ];
    return [for (final channel in Fc2LiveApi.slice(channels, page: page, pageSize: pageSize)) Fc2LiveApi.room(channel)];
  }

  // Search --------------------------------------------------------------------

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      searchRoomsCancellable(keyword, page: page, pageSize: pageSize);

  /// 3.x's search: a channel number or channel link is looked up
  /// (`memberApi`, found also when offline; only page 1, and a channel that
  /// does not exist gives nothing); any other keyword filters the snapshot
  /// (see [Fc2LiveApi.search]), page [page] of [pageSize]. A blank keyword
  /// or a page 3.x served nothing for gives nothing, without a request.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    final query = keyword.trim();
    if (query.isEmpty || !Fc2LiveApi.validSlice(page: page, pageSize: pageSize)) return const [];
    final exact = Fc2LiveApi.channelId(query);
    if (exact != null) {
      if (page != 1) return const [];
      try {
        return [Fc2LiveApi.room((await _member(exact, cancel: cancel)).channel)];
      } on NotFound {
        return const [];
      }
    }
    _checkCancelled(cancel);
    final channels = await _snapshotFor(cancel);
    return [
      for (final channel in Fc2LiveApi.slice(Fc2LiveApi.search(channels, query), page: page, pageSize: pageSize))
        Fc2LiveApi.room(channel),
    ];
  }

  // Rooms ---------------------------------------------------------------------

  /// The channel [roomId] names: a channel number, or a channel link as
  /// 3.x accepted; anything else is `NotFound` without a request.
  static String _channel(String roomId) =>
      Fc2LiveApi.channelId(roomId) ?? (throw NotFound(_site, 'room id "${roomId.trim()}" is not an FC2 channel'));

  Future<Fc2LiveMember> _member(String channelId, {CancelToken? cancel}) async {
    final response = await _post('/api/memberApi.php', {
      'channel': '1',
      'profile': '1',
      'user': '1',
      'streamid': channelId,
    }, cancel: cancel);
    return Fc2LiveApi.member(response.text, channelId: channelId, status: response.status);
  }

  Future<LiveRoom> _detail(String roomId) async => Fc2LiveApi.room((await _member(_channel(roomId))).channel);

  /// The channel's member answer (one request). A channel that is not on
  /// air is offline (3.x failed on it, see [Fc2LiveApi.member]); a
  /// restricted one keeps 3.x's unknown state and notice.
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId);

  /// The same one request (3.x).
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The same one request: recording opens its own control from the
  /// recipe.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId);

  /// Whether the channel is on air (one request). A restricted channel's
  /// state cannot be told apart for this viewer: `NeedsLogin`, as 3.x
  /// refused it (`access`).
  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    final channel = (await _member(_channel(roomId))).channel;
    if (channel.state == Fc2LiveState.restricted) throw NeedsLogin(_site, 'channel ${channel.channelId} is restricted');
    return channel.state == Fc2LiveState.live;
  }

  // Control -------------------------------------------------------------------

  /// A fresh control grant of [channelId] (3.x's `Fc2Api.controlGrant`):
  /// `memberApi.php`, then `getControlServer.php` with the channel's
  /// version. A channel that is not on air is `StreamUnavailable`, a
  /// restricted one `NeedsLogin`, both without the second request. A grant
  /// is good for one control socket, about a minute; the comment connection
  /// (M5) takes its own.
  Future<Fc2LiveGrant> controlGrant(String channelId, {CancelToken? cancel}) async {
    final id = _channel(channelId);
    final member = await _member(id, cancel: cancel);
    switch (member.channel.state) {
      case Fc2LiveState.offline:
        throw StreamUnavailable(_site, 'channel $id is not on air');
      case Fc2LiveState.restricted:
        throw NeedsLogin(_site, 'channel $id is paid, ticketed, login-only or limited');
      case Fc2LiveState.live:
        break;
    }
    final version = member.version;
    if (version == null) throw ApiChanged(_site, 'memberApi: channel $id is live without a version');
    final response = await _post('/api/getControlServer.php', {
      'channel_id': id,
      'mode': 'play',
      'orz': '',
      'channel_version': version,
      'client_version': '2.1.0\n [1]',
      'client_type': 'pc',
      'client_app': 'browser_hls',
      'ipv6': '',
    }, cancel: cancel);
    return Fc2LiveApi.grant(response.text, channelId: id, status: response.status);
  }

  /// A control of [channelId] (3.x's `Fc2ControlSession.open`): a fresh
  /// grant and its socket, open once the master is known. The caller owns
  /// it and closes it when its consumer is done; playback and recording
  /// open one each (M7, M8). [cancel] reaches the requests and the socket
  /// while it opens, not the open control.
  Future<Fc2LiveControl> openControl(String channelId, {CancelToken? cancel}) async {
    final grant = await controlGrant(channelId, cancel: cancel);
    return await Fc2LiveControl.open(
      grant,
      connector: _connector,
      route: proxy.routeFor(_site, grant.socket),
      cancel: cancel,
      startupTimeout: controlStartupTimeout,
    );
  }

  // Streams -------------------------------------------------------------------

  /// The channel of a room that can be played: this platform's room, not
  /// said to be offline (`StreamUnavailable`), not restricted (`NeedsLogin`),
  /// and live (else `StreamUnavailable`: 3.x refused every room it had not
  /// seen live).
  static String _playable(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not an FC2 Live room');
    final channelId = _channel(detail.roomId);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, 'channel $channelId is offline');
    final data = detail.data;
    if (data is Fc2LiveRoomData && data.channelId == channelId && data.state == Fc2LiveState.restricted) {
      throw NeedsLogin(_site, 'channel $channelId is restricted');
    }
    if (!detail.isLiveNow) throw StreamUnavailable(_site, 'channel $channelId is not known to be live');
    return channelId;
  }

  /// 3.x's one quality, `auto` (the site's adaptive master), for a room
  /// that can be played ([_playable]); no request. 3.x gave an offline room
  /// an empty list and refused a room without its entry data.
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    _playable(detail);
    return const [Fc2LiveApi.autoQuality];
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The recipe of the channel (3.x's owned input): no URL, no request. A
  /// quality other than `auto` is the caller's mistake. The applied quality
  /// is `auto`.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final channelId = _playable(detail);
    if ('${quality.selectionId}' != Fc2LiveApi.autoQuality.id) {
      throw ArgumentError.value(quality, 'quality', 'FC2 Live has only the auto quality');
    }
    return LivePlayUrlResolution.owned(
      input: Fc2LiveInputRecipe(channelId),
      appliedQualityData: Fc2LiveApi.autoQuality.id,
    );
  }

  /// The same recipe: every open already takes a fresh grant.
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) => resolvePlayUrlsRaw(detail: detail, quality: quality);

  // Links ---------------------------------------------------------------------

  /// The channel of a channel link (3.x's `Fc2Link`, see
  /// [Fc2LiveApi.channelIdFromUrl]), without a request.
  @override
  String? roomIdFromUrl(String url) => Fc2LiveApi.channelIdFromUrl(url);
}
