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

/// The FC2 Live adapter (3.x's `Fc2Site` and `Fc2Api`; parsing in
/// [Fc2LiveApi], the control socket in [Fc2LiveControl]).
///
/// Anonymous, like 3.x: no cookie and no account. Comments take their own
/// control socket from the arguments of room entry and recording
/// ([Fc2LiveDanmakuArgs], 26-3), in `live_danmaku`'s
/// `Fc2LiveDanmakuConnection` (M5.22); `getDanmaku` stays `EmptyDanmaku`. Every
/// request is a form POST with 3.x's headers that does not follow
/// redirects and goes as `fc2live`, so the app routes the platform through
/// its proxy setting. The requests are 3.x's:
/// - the directory, the recommendations, the area rooms and the keyword
///   search are all the `allchannellist.php` snapshot of every channel on
///   air, paged locally. Page 1 of the directory and of the search (the
///   pull to refresh) always asks anew; every other call reuses a snapshot
///   younger than [snapshotLifetime], so the pages after the first come
///   from the same snapshot as the first (26-1; see [getDirectoryPage]);
/// - a room is one `memberApi.php` request, at room entry, refresh,
///   recording and the live-status check alike; a search for a channel
///   number or link is that request too;
/// - the qualities are the ones the channel's control answer offers
///   (26-2): listing them opens a control and closes it
///   ([discoverPlayQualitiesRaw]);
/// - streams have no URL: each quality resolves to a [Fc2LiveInputRecipe]
///   that playback and recording open themselves with [openControl] (M7,
///   M8): `memberApi.php`, `getControlServer.php` and the control socket,
///   held while they play.
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
        LivePlayRecoveryResolver,
        LiveQualityDiscovery {
  /// Creates the adapter. Control sockets connect with [connector] (default
  /// [Fc2LiveControl.connect]: `dart:io` with 3.x's 15 s ping) through
  /// [proxy]'s route for `fc2live`, the one the app gives [http] too.
  /// [controlStartupTimeout] bounds a control's handshake and HLS answer;
  /// [probeControl], when given, takes over the control the quality probe
  /// opened instead of it being closed ([discoverPlayQualitiesRaw]); [now]
  /// (the snapshot's age) is injectable for tests.
  new(
    this.http, {
    this.proxy = const FixedProxyPolicy(),
    SocketConnector? connector,
    this.controlStartupTimeout = const Duration(seconds: 20),
    this.probeControl,
    DateTime Function()? now,
  }) : _connector = connector ?? Fc2LiveControl.connect,
       _now = now ?? DateTime.now;

  /// How long a snapshot is reused after it arrived (3.x's 20 s).
  static const Duration snapshotLifetime = Duration(seconds: 20);

  /// Transport.
  final LiveHttp http;

  /// Proxy routes of the control sockets.
  final ProxyPolicy proxy;

  /// Longest wait for a control's HLS answer (3.x: 20 s).
  final Duration controlStartupTimeout;

  /// Who takes over the control a quality probe opened (M7.1 notes "FC2
  /// control sharing": playback then needs no second grant and socket),
  /// typically the player's `Fc2RecipeOpener.adopt`. It then owns the
  /// control and must close it, also when it never plays it. The control
  /// was opened for `auto`, and its [Fc2LiveControl.playlists] hold every
  /// tier, so any quality can be played from it
  /// ([Fc2LiveApi.playlistFor]). Null: the probe closes its control.
  final void Function(Fc2LiveControl control)? probeControl;

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

  /// The `allchannellist` snapshot.
  ///
  /// [fresh] (page 1 of the directory or the search: the pull to refresh)
  /// always asks anew. Otherwise the last snapshot is reused while it is
  /// younger than [snapshotLifetime] after it arrived, whoever fetched it
  /// (26-1: 3.x fetched anew for every call with a cancel token, so each
  /// page of the directory and the search came from another snapshot, and
  /// rooms repeated or went missing across pages). A call without [cancel]
  /// also shares a fetch under way (3.x fetched again for every caller that
  /// came before the first answer); one with [cancel] only reuses a
  /// snapshot that has arrived, and fetches its own with the token
  /// otherwise, so cancelling it never fails another caller. The latest
  /// successful fetch becomes the shared snapshot; a failed or cancelled
  /// one is forgotten.
  Future<List<Fc2LiveChannel>> _snapshotFor({CancelToken? cancel, bool fresh = false}) async {
    if (!fresh) {
      final cached = _snapshot;
      final at = _snapshotAt;
      if (cached != null && (at == null ? cancel == null : _young(at))) {
        final channels = await cached;
        _checkCancelled(cancel);
        return channels;
      }
    }
    if (cancel == null) return await _share();
    final channels = await _fetchSnapshot(cancel: cancel);
    _snapshot = Future.value(channels);
    _snapshotAt = _now();
    return channels;
  }

  bool _young(DateTime at) {
    final age = _now().difference(at);
    return age >= Duration.zero && age < snapshotLifetime;
  }

  /// A new fetch, shared with every caller without a cancel token until it
  /// arrives, and then for [snapshotLifetime]; a failed one is forgotten.
  Future<List<Fc2LiveChannel>> _share() {
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
  /// when it is null or `all` (3.x). Page 1 (the pull to refresh) asks for
  /// a new snapshot; later pages come from the last one while it is younger
  /// than [snapshotLifetime], so they neither repeat nor skip rooms of page
  /// 1 (26-1). A page below 1 or an area that is not one of this platform's
  /// is a caller error, without a request.
  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async {
    if (page < 1) throw RangeError.range(page, 1, null, 'page');
    final filter = category == null ? null : Fc2LiveApi.areaFilter(category);
    _checkCancelled(cancel);
    final channels = await _snapshotFor(cancel: cancel, fresh: page == 1);
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
    final channels = await _snapshotFor();
    return [for (final channel in Fc2LiveApi.slice(channels, page: page, pageSize: pageSize)) Fc2LiveApi.room(channel)];
  }

  /// As [getRecommendRooms], for the area [category] (an area that is not
  /// one of this platform's is a caller error, without a request).
  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    final filter = Fc2LiveApi.areaFilter(category);
    if (!Fc2LiveApi.validSlice(page: page, pageSize: pageSize)) return const [];
    final channels = [
      for (final channel in await _snapshotFor())
        if (Fc2LiveApi.inArea(channel, filter)) channel,
    ];
    return [for (final channel in Fc2LiveApi.slice(channels, page: page, pageSize: pageSize)) Fc2LiveApi.room(channel)];
  }

  // Search --------------------------------------------------------------------

  /// As [searchRoomsCancellable], every keyword page from the shared
  /// snapshot (3.x shared it with every call without a cancel token).
  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) =>
      _search(keyword, page: page, pageSize: pageSize, fresh: false);

  /// 3.x's search: a channel number or channel link is looked up
  /// (`memberApi`, found also when offline; only page 1, and a channel that
  /// does not exist gives nothing); any other keyword filters the snapshot
  /// (see [Fc2LiveApi.search]), page [page] of [pageSize]. Page 1 asks for a
  /// new snapshot; later pages come from the last one while it is younger
  /// than [snapshotLifetime] (26-1, as [getDirectoryPage]). A blank keyword
  /// or a page 3.x served nothing for gives nothing, without a request.
  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) => _search(keyword, page: page, pageSize: pageSize, cancel: cancel, fresh: page == 1);

  Future<List<LiveRoom>> _search(
    String keyword, {
    required int page,
    required int pageSize,
    required bool fresh,
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
    final channels = await _snapshotFor(cancel: cancel, fresh: fresh);
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

  Future<LiveRoom> _detail(String roomId, {bool danmaku = false}) async =>
      Fc2LiveApi.room((await _member(_channel(roomId))).channel, danmaku: danmaku);

  /// The channel's member answer (one request). A channel that is not on
  /// air is offline (3.x failed on it, see [Fc2LiveApi.member]); a
  /// restricted one is live and marked with its restriction (26-9; 3.x
  /// showed it unknown), keeping 3.x's notice. The room carries the
  /// comment arguments (26-3, M5).
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => _detail(roomId, danmaku: true);

  /// The same one request (3.x), without the comment arguments.
  @override
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId}) => _detail(roomId);

  /// The same one request, with the comment arguments: recording opens its
  /// own control from the recipe.
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) => _detail(roomId, danmaku: true);

  /// Whether the channel is on air (one request). A restricted broadcast is
  /// on air (26-9; 3.x refused it with `access`); playing it is refused
  /// with the reason.
  @override
  Future<bool> getLiveStatus({required String roomId}) async =>
      (await _member(_channel(roomId))).channel.state != Fc2LiveState.offline;

  // Control -------------------------------------------------------------------

  /// A fresh control grant of [channelId] (3.x's `Fc2Api.controlGrant`):
  /// `memberApi.php`, then `getControlServer.php` with the channel's
  /// version. A channel that is not on air is `StreamUnavailable`, a
  /// restricted one is refused by its restriction
  /// ([Fc2LiveApi.refusal]: `NeedsLogin` for signed-in viewers only, else
  /// `StreamUnavailable` with the reason; 3.x: always `access`), both
  /// without the second request. A grant is good for one control socket,
  /// about a minute; the comment connection (M5) takes its own.
  Future<Fc2LiveGrant> controlGrant(String channelId, {CancelToken? cancel}) async {
    final id = _channel(channelId);
    final member = await _member(id, cancel: cancel);
    if (member.channel.state == Fc2LiveState.offline) throw StreamUnavailable(_site, 'channel $id is not on air');
    if (Fc2LiveApi.refusal(member.channel.restriction, id) case final refusal?) throw refusal;
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
  /// grant and its socket, open once the playlist of [quality] is known
  /// (`auto`, 3.x's master, or a tier's single variant, 26-2; a recipe's
  /// [Fc2LiveInputRecipe.quality]). The caller owns it and closes it when
  /// its consumer is done; playback and recording open one each (M7, M8).
  /// [cancel] reaches the requests and the socket while it opens, not the
  /// open control. A quality that is not one of [Fc2LiveApi.qualityIds] is
  /// the caller's mistake, without a request.
  Future<Fc2LiveControl> openControl(
    String channelId, {
    CancelToken? cancel,
    String quality = Fc2LiveApi.autoQualityId,
  }) async {
    if (!Fc2LiveApi.qualityIds.contains(quality)) throw ArgumentError.value(quality, 'quality', 'not an FC2 quality');
    final grant = await controlGrant(channelId, cancel: cancel);
    return await Fc2LiveControl.open(
      grant,
      connector: _connector,
      route: proxy.routeFor(_site, grant.socket),
      cancel: cancel,
      quality: quality,
      startupTimeout: controlStartupTimeout,
    );
  }

  // Streams -------------------------------------------------------------------

  /// The channel of a room that can be played: this platform's room, not
  /// said to be offline (`StreamUnavailable`), not restricted (refused by
  /// its restriction, [Fc2LiveApi.refusal], from the room's data or, for a
  /// stored room, its `restriction`), and live (else `StreamUnavailable`:
  /// 3.x refused every room it had not seen live).
  static String _playable(LiveRoom detail) {
    if (detail.platform != _site) throw ArgumentError.value(detail.platform, 'detail', 'not an FC2 Live room');
    final channelId = _channel(detail.roomId);
    if (detail.isExplicitlyOfflineNow) throw StreamUnavailable(_site, 'channel $channelId is offline');
    final data = detail.data;
    final restriction = data is Fc2LiveRoomData && data.channelId == channelId ? data.restriction : detail.restriction;
    if (Fc2LiveApi.refusal(restriction, channelId) case final refusal?) throw refusal;
    if (!detail.isLiveNow) throw StreamUnavailable(_site, 'channel $channelId is not known to be live');
    return channelId;
  }

  /// The qualities the room's channel offers ([discoverPlayQualitiesRaw]).
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) =>
      discoverPlayQualitiesRaw(detail: detail);

  /// The qualities the room's channel offers now (26-2), best first: a room
  /// that cannot be played is refused first, without a request
  /// ([_playable]); otherwise a control is opened ([openControl]:
  /// `memberApi.php`, `getControlServer.php` and the socket), its HLS
  /// answer read ([Fc2LiveApi.qualitiesOf]: `50` and `40` only for the
  /// channels that have them, then 3.x's `auto`) and the control closed
  /// before this returns, or handed to [probeControl] when there is one
  /// (and the answer listed qualities). Only the control's answer tells which tiers a
  /// channel has, so this costs two requests and a socket (3.x listed
  /// `auto` alone, without a request). [cancel] reaches the requests and
  /// the socket while it opens.
  @override
  Future<List<LivePlayQuality>> discoverPlayQualitiesRaw({required LiveRoom detail, CancelToken? cancel}) async {
    final channelId = _playable(detail);
    final control = await openControl(channelId, cancel: cancel);
    final List<LivePlayQuality> qualities;
    try {
      qualities = Fc2LiveApi.qualitiesOf(control.playlists);
    } on Object {
      await control.close();
      rethrow;
    }
    final taker = probeControl;
    if (taker == null || control.isClosed) {
      await control.close();
    } else {
      taker(control);
    }
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async =>
      (await resolvePlayUrlsRaw(detail: detail, quality: quality)).urls;

  /// The recipe of the channel in [quality] (3.x's owned input): no URL,
  /// no request. A quality that is not one of [Fc2LiveApi.qualities] is the
  /// caller's mistake. The applied quality is the one asked for; the
  /// control says which one plays when the channel no longer offers that
  /// tier ([Fc2LiveControl.quality], M7).
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final channelId = _playable(detail);
    final id = '${quality.selectionId}';
    if (!Fc2LiveApi.qualityIds.contains(id)) {
      throw ArgumentError.value(quality, 'quality', 'not an FC2 Live quality');
    }
    return LivePlayUrlResolution.owned(
      input: Fc2LiveInputRecipe(channelId, quality: id),
      appliedQualityData: id,
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
