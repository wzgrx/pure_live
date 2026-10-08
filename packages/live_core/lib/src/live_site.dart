import 'dart:async';

import 'package:live_core/src/hls_source_query_policy.dart';
import 'package:live_core/src/input_recipe.dart';
import 'package:live_core/src/live_area.dart';
import 'package:live_core/src/live_message.dart';
import 'package:live_core/src/live_room.dart';
import 'package:live_core/src/play_line.dart';
import 'package:live_core/src/quality_label.dart';
import 'package:live_core/src/sites.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// A platform adapter (3.x's `LiveSite`). Each call has a harmless default
/// for platforms that do not support it; extra abilities are the optional
/// interfaces below, used through the extensions on this class.
///
/// Adapters report failures as `SiteError`s (or live_net's failures), not
/// as offline-looking rooms.
abstract class LiveSite {
  /// Platform id, lower case (`douyu`).
  String get id;

  /// Display name (`斗鱼`).
  String get name;

  /// Categories with their areas.
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async => const [];

  /// Rooms matching [keyword].
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async => const [];

  /// Streamers matching [keyword].
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async => const [];

  /// Rooms of [category].
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async => const [];

  /// Recommended rooms.
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async => const [];

  /// Detail of [roomId]. The default has no platform evidence, so the state
  /// is unknown rather than an invented offline.
  Future<LiveRoom> getRoomDetail({required String roomId}) async =>
      LiveRoom(roomId: roomId, platform: id, watching: '', liveStatus: LiveStatus.unknown);

  /// Qualities of a room.
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => const [];

  /// Stream URLs of a room at [quality], in the platform's order of lines.
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => const [];

  /// Whether [roomId] is broadcasting.
  Future<bool> getLiveStatus({required String roomId}) async => false;

  /// Super chats of [roomId] (platforms that poll them).
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) async => const [];

  /// Whether the platform has super chats at all ([superChatPlatforms]), so
  /// an empty list can say the platform has none instead of "they will show
  /// up here".
  bool get hasSuperChats => superChatPlatforms.contains(id);

  /// Whether the platform is voice only ([SiteIds.voiceLive]): its picture
  /// is never a real one (A07.20).
  bool get isVoiceLive => SiteIds.voiceLive.contains(id);
}

/// The platforms with super chats (3.x: Bilibili and Huya poll them and
/// send them in the danmaku, Douyu sends them in the danmaku; every other
/// adapter keeps `getSuperChatMessage`'s empty default).
const Set<String> superChatPlatforms = {'bilibili', 'huya', 'douyu'};

/// The stream sources for one requested quality, and the quality the
/// platform actually applied.
///
/// Some platforms advertise a quality but silently downgrade anonymous
/// requests; returning only URLs made the interface show the tapped label
/// while a lower quality played. Adapters that can read the answer set
/// [appliedQualityData] to the server's stable quality id.
@immutable
final class LivePlayUrlResolution {
  /// Plain URLs (lines without metadata), with [appliedQualityData] when the
  /// platform confirmed a quality.
  new({
    required List<String> urls,
    this.appliedQualityData,
    this.qualityUnconfirmed = false,
    this.appliedQuality,
    this.start,
  }) : lines = List.unmodifiable([for (final url in urls) LivePlayLine(url)]),
       sourceQueryPolicies = const {},
       inputRecipe = null;

  /// Lines that describe themselves (headers, format, lease).
  new lines(
    List<LivePlayLine> lines, {
    this.appliedQualityData,
    this.qualityUnconfirmed = false,
    this.appliedQuality,
    this.start,
  }) : lines = List.unmodifiable(lines),
       sourceQueryPolicies = const {},
       inputRecipe = null;

  /// A source without an exportable URL (see [LiveInputRecipe]).
  const new owned({
    required LiveInputRecipe input,
    this.appliedQualityData,
    this.qualityUnconfirmed = false,
    this.appliedQuality,
    this.start,
  }) : inputRecipe = input,
       lines = const [],
       sourceQueryPolicies = const {};

  const new _({
    required this.lines,
    required this.sourceQueryPolicies,
    this.appliedQualityData,
    this.qualityUnconfirmed = false,
    this.appliedQuality,
    this.start,
  }) : inputRecipe = null;

  /// URLs with HLS query policies, validated together: each key must be one
  /// of [urls] and its policy must have been made for exactly that URL.
  factory withSourcePolicies({
    required List<String> urls,
    required Map<String, HlsSourceQueryPolicy> sourceQueryPolicies,
    Object? appliedQualityData,
    bool qualityUnconfirmed = false,
    LivePlayQuality? appliedQuality,
    Duration? start,
  }) => LivePlayUrlResolution._validated(
    [for (final url in urls) LivePlayLine(url)],
    sourceQueryPolicies,
    appliedQualityData: appliedQualityData,
    qualityUnconfirmed: qualityUnconfirmed,
    appliedQuality: appliedQuality,
    start: start,
  );

  factory _validated(
    List<LivePlayLine> lines,
    Map<String, HlsSourceQueryPolicy> sourceQueryPolicies, {
    Object? appliedQualityData,
    bool qualityUnconfirmed = false,
    LivePlayQuality? appliedQuality,
    Duration? start,
  }) {
    final normalized = normalizePlayLines(lines);
    final urls = {for (final line in normalized) line.url};
    final policies = <String, HlsSourceQueryPolicy>{};
    for (final MapEntry(:key, :value) in sourceQueryPolicies.entries) {
      final uri = Uri.tryParse(key);
      if (!urls.contains(key) || uri == null || !value.matchesSource(uri)) {
        throw const FormatException('Source query policy does not match resolved URLs');
      }
      policies[key] = value;
    }
    return LivePlayUrlResolution._(
      lines: normalized,
      sourceQueryPolicies: Map<String, HlsSourceQueryPolicy>.unmodifiable(policies),
      appliedQualityData: appliedQualityData,
      qualityUnconfirmed: qualityUnconfirmed,
      appliedQuality: appliedQuality,
      start: start,
    );
  }

  /// Lines in the platform's order.
  final List<LivePlayLine> lines;

  /// The source when it has no plain URL.
  final LiveInputRecipe? inputRecipe;

  /// The quality id the platform applied, when it said.
  final Object? appliedQualityData;

  /// HLS query policies by exact URL.
  final Map<String, HlsSourceQueryPolicy> sourceQueryPolicies;

  /// The adapter expected a confirmation but the answer had none.
  final bool qualityUnconfirmed;

  /// The quality the platform played instead of the requested one, when it
  /// switched to one the caller may not know (11-1: Picarto's recovery after
  /// the streamer changed the profile plays the new best quality): its name
  /// and [appliedQualityData] id, so the player can show it without asking
  /// for the qualities again. Null when the requested quality was played.
  final LivePlayQuality? appliedQuality;

  /// Where to start playing the source, when not at its beginning (1-1:
  /// Bilibili's carousel video at its `play_time`); null for the start, or
  /// for a live stream. `PlaybackPlan.of(start:)` takes it.
  final Duration? start;

  /// Stream URLs, one per line.
  List<String> get urls => [for (final line in lines) line.url];

  /// Number of lines.
  int get lineCount => inputRecipe == null ? lines.length : 1;

  /// Whether there is anything to play.
  bool get hasSources => lineCount > 0;

  /// This resolution with blank and duplicate URLs removed.
  LivePlayUrlResolution normalized() => inputRecipe != null
      ? this
      : LivePlayUrlResolution._validated(
          lines,
          sourceQueryPolicies,
          appliedQualityData: appliedQualityData,
          qualityUnconfirmed: qualityUnconfirmed,
          appliedQuality: appliedQuality,
          start: start,
        );
}

/// The quality to show for [resolution]: the option whose id the platform
/// confirmed, else the quality the platform says it switched to
/// ([LivePlayUrlResolution.appliedQuality], 11-1), else [requested]; marked
/// unconfirmed when the platform did not confirm it or confirmed an id
/// outside [qualities] without naming that quality.
LivePlayQuality resolveAppliedPlayQuality({
  required List<LivePlayQuality> qualities,
  required LivePlayQuality requested,
  required LivePlayUrlResolution resolution,
}) {
  final appliedId = resolution.appliedQualityData?.toString();
  final matched = appliedId == null
      ? null
      : qualities.where((quality) => quality.selectionId.toString() == appliedId).firstOrNull ??
            switch (resolution.appliedQuality) {
              final switched? when switched.selectionId.toString() == appliedId => switched,
              _ => null,
            };
  return (matched ?? requested).withPlaybackUnconfirmed(
    unconfirmed: resolution.qualityUnconfirmed || (appliedId != null && matched == null),
  );
}

/// The quality the platform served for [requested], as the live room, the
/// multi-view and the recorder show it (H01.3, C01.4): the
/// [resolveAppliedPlayQuality] answer, except that a confirmed id outside
/// [qualities] — a room listed as 原画 only, where a Bilibili guest asking
/// for 10000 is served 250 — is named by [platform]'s codes
/// ([LiveQualityLabel]) and counts as confirmed, instead of falling back to
/// the request marked unconfirmed. A platform that did not say what it was
/// expected to still gets the request, unconfirmed.
LivePlayQuality resolveServedPlayQuality({
  required String platform,
  required List<LivePlayQuality> qualities,
  required LivePlayQuality requested,
  required LivePlayUrlResolution resolution,
}) {
  final applied = resolveAppliedPlayQuality(qualities: qualities, requested: requested, resolution: resolution);
  final id = resolution.appliedQualityData;
  if (!applied.isPlaybackUnconfirmed || resolution.qualityUnconfirmed || id == null || '$id'.trim().isEmpty) {
    return applied;
  }
  return LivePlayQuality(
    quality: LiveQualityLabel.normalize(platform: platform, rawLabel: '', id: id),
    data: id,
    id: id,
  );
}

/// [lines] with trimmed URLs, without blank or repeated URLs (the first
/// line of a URL wins), in the platform's order.
List<LivePlayLine> normalizePlayLines(Iterable<LivePlayLine> lines) {
  final seen = <String>{};
  return List.unmodifiable([
    for (final line in lines)
      if (line.url.trim() case final url when url.isNotEmpty && seen.add(url))
        if (url == line.url)
          line
        else
          LivePlayLine(
            url,
            headers: line.headers,
            format: line.format,
            codec: line.codec,
            lineId: line.lineId,
            lease: line.lease,
            width: line.width,
            height: line.height,
          ),
  ]);
}

/// [urls] trimmed, without blanks and duplicates, in the platform's order.
/// Schemes are the adapter's business: IPTV sources may use other protocols.
List<String> normalizeResolvedPlayUrls(Iterable<String> urls) {
  final seen = <String>{};
  return List.unmodifiable([
    for (final raw in urls)
      if (raw.trim() case final url when url.isNotEmpty && seen.add(url)) url,
  ]);
}

/// A platform whose stream API says which quality it applied (Bilibili
/// downgrades guests even when a higher `qn` was requested).
abstract interface class LivePlayUrlResolver {
  /// URLs for [quality] with the applied quality.
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality});
}

/// A platform that needs one request per line. Recording asks for one line
/// at a time and the next only after a failure; an index past the last line
/// gives no URLs.
abstract interface class LivePlayUrlCursorResolver {
  /// The URL of line [lineIndex].
  Future<LivePlayUrlResolution> resolvePlayUrlAtRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
    required int lineIndex,
  });
}

/// A signed platform whose room data and URLs expire before the viewing
/// session: recovery must fetch every token and room field again (returning
/// the cached URLs would reopen an expired source forever).
abstract interface class LivePlayRecoveryResolver {
  /// Fresh URLs for [quality].
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  });
}

/// Lease times of short-lived signed URLs, so the player can renew before
/// the server rejects a reconnect. Null keeps a source on the error path.
abstract interface class LivePlayLeaseMetadata {
  /// When to fetch a new URL for [url].
  DateTime? getPlayUrlRefreshAt(String url, {DateTime? now});

  /// The last instant [url] can open a new connection; a prefetched URL is
  /// usable until then, an expired one is discarded.
  DateTime? getPlayUrlInvalidAt(String url, {DateTime? now});
}

/// A cheap detail for refreshing follow cards: state, title, cover and
/// audience, without the stream, signing and danmaku data a room needs.
abstract interface class LiveSiteRoomRefresher {
  /// The refresh detail of [roomId].
  Future<LiveRoom> getRoomDetailForRefresh({required String roomId});
}

/// A strict, playback-complete detail before a recording starts: transport
/// and shape failures are thrown, offline or banned only when the platform
/// said so, and every field `getPlayQualities` needs is kept.
abstract interface class LiveSiteRecordRoomResolver {
  /// The recording detail of [roomId].
  Future<LiveRoom> getRoomDetailForRecording({required String roomId});
}

/// A search that can be cancelled; the token is forwarded to the transport.
abstract interface class LiveCancellableSearch {
  /// [LiveSite.searchRooms] with [cancel].
  Future<List<LiveRoom>> searchRoomsCancellable(String keyword, {int page = 1, int pageSize = 30, CancelToken? cancel});
}

/// Per-keyword paging, for adapters that answer some keywords with one exact
/// match and others with pages.
abstract interface class LiveSearchPaginationPolicy {
  /// Whether results for [keyword] have more pages.
  bool supportsSearchPaginationFor(String keyword);
}

/// Quality discovery with its own lifetime: the transport gets the token, and
/// the result settles only after temporary sessions or credentials are
/// released. Cancelling never closes a shared client or another discovery.
abstract interface class LiveQualityDiscovery {
  /// Qualities of [detail].
  Future<List<LivePlayQuality>> discoverPlayQualitiesRaw({required LiveRoom detail, CancelToken? cancel});
}

/// One page of a platform's own directory. The number of rooms is no paging
/// evidence: a server may inject recommendations or the adapter may drop
/// closed rooms.
@immutable
final class LiveDirectoryPage {
  /// Creates a page.
  new({required Iterable<LiveRoom> rooms, required this.page, required this.hasMore, this.nextCursor})
    : rooms = List.unmodifiable(rooms);

  /// Rooms.
  final List<LiveRoom> rooms;

  /// Page number (a UI sequence for cursor platforms).
  final int page;

  /// Whether another page exists.
  final bool hasMore;

  /// Opaque server cursor for the next page.
  final String? nextCursor;
}

/// A platform with native directory pages.
abstract interface class LiveSiteDirectoryPager {
  /// Page [page] of [category], or of recommendations when null.
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel});
}

/// A cursor-paged directory: each listing passes its own last cursor, no
/// shared page-to-cursor map.
abstract interface class LiveSiteCursorDirectoryPager implements LiveSiteDirectoryPager {
  /// The page after [cursor].
  Future<LiveDirectoryPage> getDirectoryPageAtCursor({
    required int page,
    String? cursor,
    LiveArea? category,
    CancelToken? cancel,
  });
}

/// A platform whose category pages are natively paged while recommendations
/// are not; its pager needs a category.
abstract interface class LiveSiteCategoryDirectoryProvider {
  /// The category pager.
  LiveSiteDirectoryPager get categoryDirectory;
}

/// A platform that stops sending the user's stored cookie once the platform
/// refuses it and carries on anonymously (B-7): [cookieRefusals] says so, so
/// the app can tell the user once that the cookie expired and should be
/// filled in again.
abstract interface class LiveSiteCookieRefusals {
  /// One event each time a stored cookie is refused for the first time (a
  /// refused cookie is not sent again until it changes, so the same cookie
  /// is reported once). A broadcast stream that never closes; the cookie is
  /// not in the event.
  Stream<void> get cookieRefusals;
}

/// A lasting explanation of what a platform's directory covers.
abstract interface class LiveDirectoryNotice {
  /// Text key of the explanation.
  String get directoryNoticeKey;
}

/// The unified calls over the optional capabilities.
extension LiveSiteCalls on LiveSite {
  /// URLs for [quality]: the platform's confirmation when it gives one, else
  /// the requested quality is assumed applied.
  Future<LivePlayUrlResolution> resolvePlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    if (this case final LivePlayUrlResolver resolver) {
      return (await resolver.resolvePlayUrlsRaw(detail: detail, quality: quality)).normalized();
    }
    return LivePlayUrlResolution(
      urls: normalizeResolvedPlayUrls(await getPlayUrls(detail: detail, quality: quality)),
      appliedQualityData: quality.selectionId,
    );
  }

  /// URLs for recovery: fresh ones where the platform needs them.
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecovery({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    if (this case final LivePlayRecoveryResolver resolver) {
      final resolution = await resolver.resolvePlayUrlsForRecoveryRaw(detail: detail, quality: quality);
      return resolution.normalized();
    }
    return await resolvePlayUrls(detail: detail, quality: quality);
  }

  /// [LiveSite.searchRooms] that honours [cancel] (forwarded where the
  /// adapter can, else checked before and after); throws a cancelled
  /// `TransportFailure` once cancelled.
  Future<List<LiveRoom>> searchRoomsWithCancellation(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    _checkCancelled(cancel);
    final rooms = await switch (this) {
      final LiveCancellableSearch search => search.searchRoomsCancellable(
        keyword,
        page: page,
        pageSize: pageSize,
        cancel: cancel,
      ),
      _ => searchRooms(keyword, page: page, pageSize: pageSize),
    };
    _checkCancelled(cancel);
    return rooms;
  }

  /// Qualities of [detail], honouring [cancel] like
  /// [searchRoomsWithCancellation]: a cancelled result is never passed on.
  Future<List<LivePlayQuality>> discoverPlayQualities({required LiveRoom detail, CancelToken? cancel}) async {
    _checkCancelled(cancel);
    final result = await switch (this) {
      final LiveQualityDiscovery discovery => discovery.discoverPlayQualitiesRaw(detail: detail, cancel: cancel),
      _ => getPlayQualities(detail: detail),
    };
    _checkCancelled(cancel);
    return result;
  }

  void _checkCancelled(CancelToken? cancel) {
    if (cancel?.isCancelled ?? false) throw TransportFailure(id, TransportReason.cancelled);
  }
}

/// One consumer's quality-discovery lifetime, apart from detail and URL
/// requests and from the player. [close] cancels and waits for the cleanup
/// of capability-owned discoveries.
final class LiveQualityDiscoveryScope {
  /// The scope's cancellation.
  final CancelToken cancelToken = CancelToken();
  final Set<Future<void>> _pending = {};
  Future<void>? _closing;

  /// Throws a cancelled failure once the scope is cancelled.
  void checkActive(String site) {
    if (cancelToken.isCancelled) throw TransportFailure(site, TransportReason.cancelled);
  }

  /// Qualities of [detail] on [site] within this scope.
  Future<List<LivePlayQuality>> discover(LiveSite site, LiveRoom detail) async {
    checkActive(site.id);
    final cleanup = Completer<void>();
    if (site is LiveQualityDiscovery) _pending.add(cleanup.future);
    try {
      return await site.discoverPlayQualities(detail: detail, cancel: cancelToken);
    } finally {
      _pending.remove(cleanup.future);
      cleanup.complete();
    }
  }

  /// Cancels running discoveries.
  void cancel() => cancelToken.cancel();

  /// Cancels and waits for capability-owned cleanup.
  Future<void> close() {
    cancel();
    return _closing ??= Future.wait(_pending.toList()).then((_) {});
  }
}
