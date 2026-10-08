import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_media/src/proxy.dart';
import 'package:live_media/src/relay/flv_splicer.dart';
import 'package:live_media/src/relay/hls_relay.dart';
import 'package:live_media/src/relay/loopback_relay.dart';
import 'package:live_media/src/source.dart';
import 'package:live_net/live_net.dart';

/// What the engine opens for one source: a URL with its headers, or a
/// loopback URL of the relay that owns the upstream (3.x's
/// `PlaybackInputLease` plus the arguments of its `PlaybackNativeOpen`).
abstract interface class MediaInput {
  /// The source this input is for.
  PlaybackSource get source;

  /// How the source reaches the engine.
  MediaRoute get route;

  /// The URL the engine opens.
  Uri get uri;

  /// Request headers for the engine; empty for a loopback input.
  Map<String, String> get headers;

  /// A loopback input: the engine must not proxy it, and nothing about it
  /// may be logged as a media URL (3.x's `privateInput`).
  bool get private;

  /// mpv's `http-proxy` for this input ('' for none).
  String get proxyUrl;

  /// A recording rather than a live stream.
  bool get onDemand;

  /// Where to start an on-demand input.
  Duration? get start;

  /// The line the input streams now (changes when the relay renews it);
  /// null for a recipe.
  LivePlayLine? get line;

  /// False once the input closed or its grant ended (a niconico seat, an
  /// FC2 control): recovery opens the source again instead of reopening
  /// [uri] (3.x's `activeInputIsUsable`).
  bool get isUsable;

  /// Releases the input; idempotent.
  Future<void> close();
}

/// An input opened from a recipe: its relay input plus whatever grant it
/// holds.
abstract interface class OwnedInput {
  /// The relayed playlist.
  RelayInput get relay;

  /// Whether the grant still holds.
  bool get isUsable;

  /// Releases the relay input and the grant.
  Future<void> close();
}

/// Opens one kind of recipe for playback (3.x's `BigoPlaybackInput`,
/// `Fc2PlaybackInput`, `NiconicoPlaybackInput`). Every call acquires its
/// own grant; nothing is shared with recording or other players.
abstract interface class RecipeOpener {
  /// Whether this opener handles [recipe].
  bool handles(LiveInputRecipe recipe);

  /// Opens [recipe] on [relay]. A cancelled [cancel] opens nothing; a grant
  /// acquired before a cancellation is released before this throws.
  Future<OwnedInput> open(LiveInputRecipe recipe, LoopbackRelay relay, {CancelToken? cancel});
}

/// Turns sources into engine inputs, starting the loopback relay on first
/// need (archive v4's `SourcePipeline`, with 3.x's routes).
final class MediaOpener {
  /// Creates an opener. [relay] returns a shared relay the caller owns; by
  /// default the opener starts its own on first need with [proxy], and
  /// [close] stops it. [recipes] open the platforms' input recipes.
  new({
    this.proxy = const FixedProxyPolicy(),
    this.engine = const EngineProfile(),
    this.recipes = const [],
    Future<LoopbackRelay> Function()? relay,
  }) : _startRelay = relay,
       _ownsRelay = relay == null;

  /// Proxy routes, for the engine and the relay.
  final ProxyPolicy proxy;

  /// What the engine can read.
  final EngineProfile engine;

  /// Openers of input recipes.
  final List<RecipeOpener> recipes;

  final Future<LoopbackRelay> Function()? _startRelay;
  final bool _ownsRelay;
  Future<LoopbackRelay>? _relay;

  Future<LoopbackRelay> _relayNow() => _relay ??= (_startRelay ?? () => LoopbackRelay.start(proxy: proxy)).call();

  /// Opens [source] of platform [site] (the proxy route key).
  ///
  /// With [renew], a line whose lease cuts the connection is relayed and
  /// renewed in place; [onRenewed] receives each renewed line. [queryPolicy]
  /// is the resolution's policy for the line ([PlaybackPlan.queryPolicyFor]);
  /// [variantSelector] its selector ([PlaybackPlan.variantSelectorFor]): the
  /// relay serves every copy of the line's master restricted to that variant
  /// and its audio, and a copy without it fails (G01.4).
  Future<MediaInput> open(
    PlaybackSource source, {
    required String site,
    LineRenewer? renew,
    HlsSourceQueryPolicy? queryPolicy,
    HlsVariantSelector? variantSelector,
    void Function(LivePlayLine line)? onRenewed,
    void Function(SpliceEvent event)? onEvent,
    bool onDemand = false,
    Duration? start,
    CancelToken? cancel,
  }) async {
    if (cancel?.isCancelled ?? false) throw TransportFailure(site, TransportReason.cancelled);
    switch (source) {
      case LineSource(:final line):
        final route = MediaRoute.of(
          line,
          engine: engine,
          canRenew: renew != null,
          queryPolicy: queryPolicy,
          variantSelector: variantSelector,
        );
        switch (route) {
          case MediaRoute.direct || MediaRoute.owned:
            final url = Uri.parse(line.url);
            return _DirectInput(source, line, url, engineProxyUrl(proxy, site, url), onDemand: onDemand, start: start);
          case MediaRoute.flvSplice || MediaRoute.flvRewrite:
            final relay = await _relayNow();
            final input = relay.openFlv(
              line,
              site: site,
              renew: route == MediaRoute.flvSplice ? renew : null,
              rewriteLegacyHevc: engine.rewriteLegacyHevcFlv && engine.mayCarryLegacyHevc(line),
              onRenewed: onRenewed,
              onEvent: onEvent,
            );
            return _RelayedInput(source, route, input, null, onDemand: onDemand, start: start);
          case MediaRoute.hlsRelay:
            if (queryPolicy != null && !queryPolicy.matchesSource(Uri.parse(line.url))) {
              throw const FormatException('Playback query policy does not match selected input');
            }
            final relay = await _relayNow();
            final input = relay.openHls(
              line,
              site: site,
              recipe: HlsRelayRecipe(
                queryPolicy: queryPolicy,
                master: variantSelector == null
                    ? null
                    : (source, text) => variantSelector.selectIn(text, source: source).rewrite(source, text),
              ),
              renew: (line.lease?.cutsConnection ?? false) && renew != null
                  ? (current) async {
                      final next = await renew(current);
                      onRenewed?.call(next);
                      return next;
                    }
                  : null,
            );
            return _RelayedInput(source, route, input, null, onDemand: onDemand, start: start);
        }
      case RecipeSource(:final recipe):
        final opener = recipes.where((opener) => opener.handles(recipe)).firstOrNull;
        if (opener == null) throw UnsupportedError('No playback binding for ${recipe.identity}');
        final owned = await opener.open(recipe, await _relayNow(), cancel: cancel);
        return _RelayedInput(source, MediaRoute.owned, owned.relay, owned, onDemand: onDemand, start: start);
    }
  }

  /// Stops the relay if this opener started it.
  Future<void> close() async {
    final relay = _relay;
    _relay = null;
    if (relay != null && _ownsRelay) await (await relay).close();
  }
}

final class _DirectInput implements MediaInput {
  new(this.source, this.line, this.uri, this.proxyUrl, {required this.onDemand, required this.start});

  @override
  final PlaybackSource source;

  @override
  final LivePlayLine line;

  @override
  final Uri uri;

  @override
  final String proxyUrl;

  @override
  final bool onDemand;

  @override
  final Duration? start;

  var _closed = false;

  @override
  MediaRoute get route => MediaRoute.direct;

  @override
  Map<String, String> get headers => line.headers;

  @override
  bool get private => false;

  @override
  bool get isUsable => !_closed;

  @override
  Future<void> close() async => _closed = true;
}

final class _RelayedInput implements MediaInput {
  new(this.source, this.route, this._input, this._owned, {required this.onDemand, required this.start});

  @override
  final PlaybackSource source;

  @override
  final MediaRoute route;

  final RelayInput _input;
  final OwnedInput? _owned;

  @override
  final bool onDemand;

  @override
  final Duration? start;

  Future<void>? _closing;

  @override
  Uri get uri => _input.uri;

  @override
  Map<String, String> get headers => const {};

  @override
  bool get private => true;

  @override
  String get proxyUrl => '';

  @override
  LivePlayLine? get line => _owned == null ? _input.line : null;

  @override
  bool get isUsable => _closing == null && !_input.isClosed && (_owned?.isUsable ?? true);

  @override
  Future<void> close() => _closing ??= _owned?.close() ?? _input.close();
}
