import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

/// A selected source, distinct from the URI an engine opens (3.x's
/// `PlaybackSource`). Only a line has a reusable media URL; a recipe is
/// opened afresh by every consumer and never exports one.
@immutable
sealed class PlaybackSource {
  const new();

  /// The media URL; null for a recipe.
  String? get url;

  /// Stable identity, for comparing selections.
  String get identity;
}

/// A plain line (3.x's `UrlPlaybackSource`, now with its headers, format,
/// codec and lease).
final class LineSource extends PlaybackSource {
  /// Creates the source.
  const new(this.line);

  /// The line.
  final LivePlayLine line;

  @override
  String get url => line.url;

  @override
  String get identity => line.url;

  @override
  bool operator ==(Object other) => other is LineSource && other.line.url == line.url;

  @override
  int get hashCode => line.url.hashCode;

  @override
  String toString() => 'LineSource($line)';
}

/// A source without an exportable URL (3.x's `OwnedPlaybackSource`): Bigo,
/// FC2, niconico. Like 3.x, equality is object identity: a rebuilt recipe
/// with the same label is a new source and inherits nothing from the old.
final class RecipeSource extends PlaybackSource {
  /// Creates the source.
  const new(this.recipe);

  /// The recipe.
  final LiveInputRecipe recipe;

  @override
  String? get url => null;

  @override
  String get identity => recipe.identity;

  @override
  String toString() => 'RecipeSource(${recipe.identity})';
}

/// What the engine can do, as far as source routing cares.
@immutable
final class EngineProfile {
  /// Creates a profile.
  const new({this.rewriteLegacyHevcFlv = false, this.legacyHevcHosts = const {'.17app.co'}});

  /// Whether codec-id-12 HEVC FLV must be rewritten to Enhanced FLV before
  /// the engine sees it. 3.x's libmpv had FFmpeg 7.1, which drops it; v4's
  /// native packages ship FFmpeg 9.0.2, which reads it, so the default is
  /// off. M7.2 turns it on for a build whose FFmpeg is older than 8.0.
  final bool rewriteLegacyHevcFlv;

  /// Host suffixes known to serve codec-id-12 HEVC without saying so in the
  /// line's codec (3.x: 17LIVE's CDN). Lines marked `hevc` qualify anyway.
  final Set<String> legacyHevcHosts;

  /// Whether the FLV [line] may carry codec-id-12 HEVC.
  bool mayCarryLegacyHevc(LivePlayLine line) {
    if (line.codec == 'hevc') return true;
    final host = Uri.tryParse(line.url)?.host.toLowerCase() ?? '';
    return legacyHevcHosts.any(host.endsWith);
  }
}

/// How a line reaches the engine, checked in this order.
enum MediaRoute {
  /// FLV whose lease cuts the connection, with a renewer: the relay splices
  /// renewals in (Douyu).
  flvSplice,

  /// FLV that may carry codec-id-12 HEVC on an engine that cannot read it:
  /// the relay rewrites the tags.
  flvRewrite,

  /// HLS the engine cannot fetch by itself: token propagation (a query
  /// policy), a lease that cuts the connection with a renewer (CHZZK,
  /// PandaTV), or a master to restrict to one variant (a variant selector,
  /// Steam, G01.4).
  hlsRelay,

  /// A recipe: the relay serves the consumer's own grant (Bigo, FC2,
  /// niconico).
  owned,

  /// Everything else: the engine connects to the CDN itself.
  direct;

  /// The route of [line] on [engine]. Splicing and HLS renewal need
  /// [canRenew]; [queryPolicy] and [variantSelector] are the resolution's
  /// policy and selector for the line.
  static MediaRoute of(
    LivePlayLine line, {
    required EngineProfile engine,
    required bool canRenew,
    HlsSourceQueryPolicy? queryPolicy,
    HlsVariantSelector? variantSelector,
  }) {
    final cuts = line.lease?.cutsConnection ?? false;
    final format = line.format ?? _formatOf(line.url);
    if (format == StreamFormat.flv) {
      if (canRenew && cuts) return flvSplice;
      if (engine.rewriteLegacyHevcFlv && engine.mayCarryLegacyHevc(line)) return flvRewrite;
      return direct;
    }
    if (format == StreamFormat.hls && (queryPolicy != null || variantSelector != null || (canRenew && cuts))) {
      return hlsRelay;
    }
    return direct;
  }

  static StreamFormat? _formatOf(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.flv')) return StreamFormat.flv;
    if (path.endsWith('.m3u8')) return StreamFormat.hls;
    return null;
  }
}

/// The sources of one quality in the order to try them, and what applies to
/// all of them.
@immutable
final class PlaybackPlan {
  /// Creates a plan.
  new({
    required List<PlaybackSource> sources,
    this.queryPolicies = const {},
    this.variantSelectors = const {},
    this.appliedQualityData,
    this.onDemand = false,
    this.start,
  }) : sources = List.unmodifiable(sources);

  /// The plan of [resolution] (live_core's answer for one quality).
  ///
  /// With [preferH264] (the "优先 H.264" setting, default on; upgrade 22-3)
  /// lines marked `hevc` move behind the others, keeping the platform's
  /// order otherwise. [onDemand] marks a replay (Huya 3-1, Weibo 18-5,
  /// Baidu 30-4: the room is `LiveStatus.replay`) whose end is not a
  /// failure; [start] is where to begin (Bilibili's carousel `play_time`).
  factory of(LivePlayUrlResolution resolution, {bool preferH264 = true, bool onDemand = false, Duration? start}) {
    final recipe = resolution.inputRecipe;
    if (recipe != null) {
      return PlaybackPlan(
        sources: [RecipeSource(recipe)],
        appliedQualityData: resolution.appliedQualityData,
        onDemand: onDemand,
        start: start,
      );
    }
    final lines = resolution.normalized().lines;
    final ordered = preferH264
        ? [...lines.where((line) => line.codec != 'hevc'), ...lines.where((line) => line.codec == 'hevc')]
        : lines;
    return PlaybackPlan(
      sources: [for (final line in ordered) LineSource(line)],
      queryPolicies: resolution.sourceQueryPolicies,
      variantSelectors: resolution.sourceVariantSelectors,
      appliedQualityData: resolution.appliedQualityData,
      onDemand: onDemand,
      start: start,
    );
  }

  /// Sources in the order to try them.
  final List<PlaybackSource> sources;

  /// HLS query policies by exact URL.
  final Map<String, HlsSourceQueryPolicy> queryPolicies;

  /// HLS variant selectors by exact URL (G01.4).
  final Map<String, HlsVariantSelector> variantSelectors;

  /// The quality the platform applied, when it said.
  final Object? appliedQualityData;

  /// A recording rather than a live stream: its end is normal and it seeks.
  final bool onDemand;

  /// Where to start an on-demand source.
  final Duration? start;

  /// The plain lines, in order.
  List<LivePlayLine> get lines => [
    for (final source in sources)
      if (source case LineSource(:final line)) line,
  ];

  /// Whether there is anything to play.
  bool get isEmpty => sources.isEmpty;

  /// The query policy of [source], if any.
  HlsSourceQueryPolicy? queryPolicyFor(PlaybackSource source) => switch (source) {
    LineSource(:final line) => queryPolicies[line.url],
    RecipeSource() => null,
  };

  /// The variant selector of [source], if any: its master plays restricted
  /// to that variant (G01.4).
  HlsVariantSelector? variantSelectorFor(PlaybackSource source) => switch (source) {
    LineSource(:final line) => variantSelectors[line.url],
    RecipeSource() => null,
  };
}
