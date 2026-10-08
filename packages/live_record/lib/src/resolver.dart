import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/src/settings.dart';
import 'package:meta/meta.dart';

/// Why a stream could not be resolved (3.x `StreamErrorType`, plus
/// [restricted]).
enum RecordStreamErrorType {
  /// No such room.
  roomNotFound,

  /// The room is offline.
  notLive,

  /// The room has no quality right now.
  noQuality,

  /// Every line failed.
  cdnFailed,

  /// A request failed; retrying may help.
  networkError,

  /// The platform needs a signed-in account.
  loginExpired,

  /// The room is banned.
  banned,

  /// A paid, private, members-only or region-locked broadcast whose stream
  /// this client cannot get (upgrade 22-1: say why instead of retrying).
  restricted,

  /// Anything else.
  unknown,
}

/// A resolution failure.
final class RecordStreamException implements Exception {
  /// Creates the failure.
  const new(this.type, this.message, {this.retryable = true, this.restriction});

  /// Kind.
  final RecordStreamErrorType type;

  /// Diagnostic text (sanitized before it is stored).
  final String message;

  /// Whether resolving again later can succeed.
  final bool retryable;

  /// The room's restriction for [RecordStreamErrorType.restricted].
  final LiveRestriction? restriction;

  /// The failure stage stored on the task (3.x `_streamFailureStage`).
  String get stage => switch (type) {
    RecordStreamErrorType.roomNotFound || RecordStreamErrorType.notLive || RecordStreamErrorType.banned => 'room',
    RecordStreamErrorType.restricted => 'room',
    RecordStreamErrorType.noQuality => 'quality',
    RecordStreamErrorType.cdnFailed || RecordStreamErrorType.loginExpired => 'stream',
    RecordStreamErrorType.networkError || RecordStreamErrorType.unknown => 'network',
  };

  @override
  String toString() => 'RecordStreamException(${type.name}: $message, retryable: $retryable)';
}

/// The source of one attempt, with the cursor that produced it (3.x
/// `ResolvedRecordStream`). Lease times come from the line itself (v4 lines
/// describe themselves) rather than the 3.x `LivePlayLeaseMetadata` lookup.
@immutable
final class ResolvedRecordStream {
  /// Creates the result.
  const new({
    required this.source,
    required this.quality,
    required this.qualityCursorId,
    required this.lineIndex,
    this.queryPolicy,
  });

  /// The line or recipe to record.
  final PlaybackSource source;

  /// The applied quality.
  final LivePlayQuality quality;

  /// Id of the requested quality (the retry cursor).
  final String qualityCursorId;

  /// Index of the line (the retry cursor).
  final int lineIndex;

  /// HLS query policy of the line.
  final HlsSourceQueryPolicy? queryPolicy;

  /// The line; null for a recipe.
  LivePlayLine? get line => switch (source) {
    LineSource(:final line) => line,
    RecipeSource() => null,
  };

  /// When to fetch the next URL, if the line has a lease.
  DateTime? get refreshAt => line?.lease?.refreshAt;

  /// Last instant the URL opens new connections, if known.
  DateTime? get invalidAt => line?.lease?.expiresAt;

  /// Whether this stream can still open a connection at [now].
  bool usableAt(DateTime now) => invalidAt == null || invalidAt!.isAfter(now);

  /// Display label of the line (3.x `线路N`).
  String get lineLabel => '线路${lineIndex + 1}';

  /// The recording's quality as the task shows it: the served [quality],
  /// with the player's `?` when the platform did not confirm it (3.x
  /// `playbackLabel`).
  String get qualityLabel => quality.isPlaybackUnconfirmed ? '${quality.quality}?' : quality.quality;

  /// Whether the platform confirmed another quality than the one asked for
  /// (a Bilibili guest asking for 原画 is served 超清).
  bool get qualityLimited => !quality.isPlaybackUnconfirmed && quality.selectionId.toString() != qualityCursorId;
}

const _recordableSchemes = {'http', 'https', 'rtmp', 'rtmps', 'rtsp', 'rtp', 'udp', 'tcp', 'srt', 'file'};

/// Picks the stream of one recording attempt (3.x `StreamResolverService`).
///
/// Strict room detail (`LiveSiteRecordRoomResolver`), then only the tier the
/// attempt needs: the same quality and line when renewing, the next line of
/// the previous quality after a failure, then the next qualities, and
/// finally line 1 of the previous quality again with a fresh signature.
final class RecordStreamResolver {
  /// Creates a resolver over [sites] (`SiteRegistry.maybeOf`).
  const new(this.sites);

  /// The adapter of a platform, or null when unsupported.
  final LiveSite? Function(String platform) sites;

  /// Resolves a stream of [roomId] on [platform] with the quality closest
  /// to [preferredQuality] ([preferH264]: see [orderQualities]).
  /// [previousQualityId] and [previousLineIndex] are the last attempt's
  /// cursor; [renewCurrent] asks for the same quality and line with a fresh
  /// URL.
  Future<ResolvedRecordStream> resolve({
    required String roomId,
    required String platform,
    required String preferredQuality,
    bool preferH264 = false,
    String? previousQualityId,
    int? previousLineIndex,
    bool renewCurrent = false,
    LiveQualityDiscoveryScope? discovery,
  }) async {
    final id = platform.trim().toLowerCase();
    final room = roomId.trim();
    if (room.isEmpty) {
      throw const RecordStreamException(RecordStreamErrorType.roomNotFound, 'Room id is empty', retryable: false);
    }
    final site = sites(id);
    if (site == null) {
      throw RecordStreamException(RecordStreamErrorType.unknown, 'Unsupported live site: $id', retryable: false);
    }
    discovery?.checkActive(id);
    final LiveRoom detail;
    try {
      detail = site is LiveSiteRecordRoomResolver
          ? await (site as LiveSiteRecordRoomResolver).getRoomDetailForRecording(roomId: room)
          : await site.getRoomDetail(roomId: room);
    } on NotFound catch (error) {
      throw RecordStreamException(RecordStreamErrorType.roomNotFound, '$error', retryable: false);
    } on NeedsLogin catch (error) {
      throw RecordStreamException(RecordStreamErrorType.loginExpired, '$error', retryable: false);
    } on Object catch (error) {
      discovery?.checkActive(id);
      // A transient metadata failure must retry, never look offline.
      throw RecordStreamException(RecordStreamErrorType.networkError, 'Room detail failed: $error');
    }
    discovery?.checkActive(id);
    if (detail.effectiveLiveStatus == LiveStatus.banned) {
      throw const RecordStreamException(RecordStreamErrorType.banned, 'Room banned', retryable: false);
    }
    if (!detail.isPlayableNow) {
      if (detail.isExplicitlyOfflineNow) {
        throw const RecordStreamException(RecordStreamErrorType.notLive, 'Not live', retryable: false);
      }
      throw const RecordStreamException(RecordStreamErrorType.networkError, 'Room state unknown');
    }
    try {
      return await _resolveLive(
        site,
        detail,
        preferredQuality: preferredQuality,
        preferH264: preferH264,
        previousQualityId: previousQualityId,
        previousLineIndex: previousLineIndex,
        renewCurrent: renewCurrent,
        discovery: discovery,
      );
    } on RecordStreamException catch (error) {
      discovery?.checkActive(id);
      if (detail.isRestricted) {
        throw RecordStreamException(
          RecordStreamErrorType.restricted,
          error.message,
          retryable: false,
          restriction: detail.effectiveRestriction,
        );
      }
      rethrow;
    }
  }

  Future<ResolvedRecordStream> _resolveLive(
    LiveSite site,
    LiveRoom detail, {
    required String preferredQuality,
    required bool preferH264,
    required String? previousQualityId,
    required int? previousLineIndex,
    required bool renewCurrent,
    required LiveQualityDiscoveryScope? discovery,
  }) async {
    final List<LivePlayQuality> qualities;
    try {
      qualities = discovery == null
          ? await site.discoverPlayQualities(detail: detail)
          : await discovery.discover(site, detail);
    } on Object catch (error) {
      discovery?.checkActive(site.id);
      throw RecordStreamException(RecordStreamErrorType.networkError, 'Qualities failed: $error');
    }
    if (qualities.isEmpty) {
      throw const RecordStreamException(RecordStreamErrorType.noQuality, 'No quality');
    }
    final ordered = orderQualities(qualities, preferredQuality, preferH264: preferH264);
    final cursor = site is LivePlayUrlCursorResolver;
    final previousIndex = previousQualityId == null
        ? -1
        : ordered.indexWhere((quality) => quality.selectionId.toString() == previousQualityId);
    Object? lastError;
    _Resolved? previous;

    Future<_Resolved> resolveAt(int index, int? line) async {
      discovery?.checkActive(site.id);
      final resolved = await _resolveQuality(site, detail, ordered, ordered[index], line);
      discovery?.checkActive(site.id);
      return resolved;
    }

    if (previousIndex >= 0) {
      if (renewCurrent) {
        try {
          final renewed = await resolveAt(previousIndex, cursor ? (previousLineIndex ?? 0).clamp(0, 1 << 20) : null);
          if (renewed.count > 0) {
            return renewed.select(cursor ? 0 : (previousLineIndex ?? 0).clamp(0, renewed.count - 1));
          }
        } on Object catch (error) {
          lastError = error;
        }
      }
      try {
        final nextLine = (previousLineIndex ?? -1) + 1;
        previous = await resolveAt(previousIndex, cursor ? nextLine : null);
        if (cursor && previous.count > 0) return previous.select(0);
        if (!cursor && nextLine >= 0 && nextLine < previous.count) return previous.select(nextLine);
      } on Object catch (error) {
        lastError = error;
      }
    }
    final startIndex = previousIndex < 0 ? 0 : previousIndex + 1;
    final tries = previousIndex < 0 ? ordered.length : ordered.length - 1;
    for (var offset = 0; offset < tries; offset++) {
      try {
        final resolved = await resolveAt((startIndex + offset) % ordered.length, cursor ? 0 : null);
        if (resolved.count > 0) return resolved.select(0);
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (previousIndex >= 0) {
      try {
        final wrapped = cursor ? await resolveAt(previousIndex, 0) : previous;
        if (wrapped != null && wrapped.count > 0) return wrapped.select(0);
      } on Object catch (error) {
        lastError = error;
      }
    }
    discovery?.checkActive(site.id);
    throw RecordStreamException(
      RecordStreamErrorType.cdnFailed,
      lastError == null ? 'All lines failed' : 'All lines failed: $lastError',
    );
  }

  /// [source] best first by the platform's rank (`sort`, then its order),
  /// duplicates removed, with the tier closest to the five-level
  /// [preferredQuality] moved to the front (3.x `orderQualities`: platform
  /// ids are not comparable, so only names and positions are used).
  ///
  /// With [preferH264] (the player's "优先 H.264", for a task that does not
  /// name its quality) an HEVC quality ([LivePlayQuality.codec]) is not put
  /// first while the room offers another: the nearest other one is, the
  /// better one on a tie (H01.7; the player's G01.3 rule). Inke's 原画 is
  /// Zego's HEVC in FLV (codec 12), which few players other than ours open.
  static List<LivePlayQuality> orderQualities(
    List<LivePlayQuality> source,
    String preferredQuality, {
    bool preferH264 = false,
  }) {
    final seen = <String>{};
    final indexed = source.indexed.where((entry) => seen.add(entry.$2.selectionId.toString())).toList();
    if (indexed.isEmpty) return const [];
    if (indexed.any((entry) => entry.$2.sort != 0)) {
      indexed.sort((left, right) {
        final bySort = right.$2.sort.compareTo(left.$2.sort);
        return bySort != 0 ? bySort : left.$1.compareTo(right.$1);
      });
    }
    final qualities = [for (final entry in indexed) entry.$2];
    if (qualities.length < 2) return List.unmodifiable(qualities);
    String normalize(String value) => value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    final wanted = normalize(preferredQuality);
    final exact = qualities.indexWhere((quality) => normalize(quality.quality) == wanted);
    if (exact >= 0) return _moveToFront(qualities, _avoidHevc(qualities, exact, preferH264: preferH264));
    var preference = recordQualityPreferences.indexOf(preferredQuality);
    if (preference < 0) preference = 0;
    final target = preference / (recordQualityPreferences.length - 1);
    var closest = 0;
    var distance = double.infinity;
    for (var index = 0; index < qualities.length; index++) {
      final candidate = (index / (qualities.length - 1) - target).abs();
      if (candidate < distance) {
        closest = index;
        distance = candidate;
      }
    }
    return _moveToFront(qualities, _avoidHevc(qualities, closest, preferH264: preferH264));
  }

  static int _avoidHevc(List<LivePlayQuality> qualities, int index, {required bool preferH264}) {
    bool hevc(int at) => qualities[at].codec == 'hevc';
    if (!preferH264 || !hevc(index)) return index;
    for (var distance = 1; distance < qualities.length; distance++) {
      for (final at in [index - distance, index + distance]) {
        if (at >= 0 && at < qualities.length && !hevc(at)) return at;
      }
    }
    return index;
  }

  /// The quality the platform served for [requested]: the option of
  /// [qualities] whose id it confirmed (`resolveAppliedPlayQuality`, as the
  /// player); a confirmed id outside [qualities] — a room listed as 原画
  /// only, where a Bilibili guest asking for 10000 is served 250 — named by
  /// the platform's codes ([LiveQualityLabel]) instead of falling back to
  /// the request; else [requested], unconfirmed when the platform did not
  /// say what it was expected to.
  static LivePlayQuality servedQuality({
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

  static List<LivePlayQuality> _moveToFront(List<LivePlayQuality> qualities, int index) =>
      List.unmodifiable([qualities[index], ...qualities.take(index), ...qualities.skip(index + 1)]);

  static Future<_Resolved> _resolveQuality(
    LiveSite site,
    LiveRoom detail,
    List<LivePlayQuality> ordered,
    LivePlayQuality requested,
    int? lineIndex,
  ) async {
    final resolution = site is LivePlayUrlCursorResolver && lineIndex != null
        ? (await (site as LivePlayUrlCursorResolver).resolvePlayUrlAtRaw(
            detail: detail,
            quality: requested,
            lineIndex: lineIndex,
          )).normalized()
        : await site.resolvePlayUrls(detail: detail, quality: requested);
    final applied = servedQuality(platform: site.id, qualities: ordered, requested: requested, resolution: resolution);
    final requestedId = requested.selectionId.toString();
    final recipe = resolution.inputRecipe;
    // A cursor adapter has one logical owned line; past line 0 it is used up.
    if (recipe != null) {
      return lineIndex == null || lineIndex == 0
          ? _Resolved.recipe(recipe, applied, requestedId)
          : _Resolved.lines(const [], const [], applied, requestedId, const {});
    }
    final seen = <String>{};
    final lines = <LivePlayLine>[];
    final indexes = <int>[];
    for (final line in resolution.lines) {
      final uri = Uri.tryParse(line.url);
      if (uri == null || !uri.hasScheme || !_recordableSchemes.contains(uri.scheme.toLowerCase())) continue;
      // Signed queries change on every resolve; the CDN is scheme, host, path.
      if (!seen.add(line.url.split('#').first.split('?').first)) continue;
      lines.add(line);
      indexes.add(lineIndex ?? indexes.length);
    }
    return _Resolved.lines(lines, indexes, applied, requestedId, resolution.sourceQueryPolicies);
  }
}

final class _Resolved {
  new lines(this._lines, this._indexes, this.applied, this.requestedId, this._policies) : _recipe = null;

  new recipe(LiveInputRecipe recipe, this.applied, this.requestedId)
    : _recipe = recipe,
      _lines = const [],
      _indexes = const [],
      _policies = const {};

  final LiveInputRecipe? _recipe;
  final List<LivePlayLine> _lines;
  final List<int> _indexes;
  final Map<String, HlsSourceQueryPolicy> _policies;
  final LivePlayQuality applied;
  final String requestedId;

  int get count => _recipe == null ? _lines.length : 1;

  ResolvedRecordStream select(int position) {
    final recipe = _recipe;
    if (recipe != null) {
      return ResolvedRecordStream(
        source: RecipeSource(recipe),
        quality: applied,
        qualityCursorId: requestedId,
        lineIndex: 0,
      );
    }
    final index = position.clamp(0, _lines.length - 1);
    final line = _lines[index];
    return ResolvedRecordStream(
      source: LineSource(line),
      quality: applied,
      qualityCursorId: requestedId,
      lineIndex: _indexes[index],
      queryPolicy: _policies[line.url],
    );
  }
}
