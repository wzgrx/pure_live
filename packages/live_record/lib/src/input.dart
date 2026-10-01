import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_record/src/resolver.dart';

/// Opens the stream of a recording attempt through live_media's loopback
/// relay (M7.1 left recording to reuse it).
///
/// Like 3.x, every live FLV and HLS line is relayed, not only the ones the
/// player relays: closing the relay input ends FFmpeg's input cleanly, so
/// FFmpeg drains its muxer and the last segment is complete (3.x's
/// `FFmpegFlvInputRelay` and `FFmpegHlsInputRelay` existed for this), and
/// HLS children are fetched by Dart with the platform's certificate checks
/// (FFmpeg does not pass `ca_file` to HLS child requests). A lease that cuts
/// the connection is renewed inside the relay (FLV splicing, HLS renewal):
/// the recording continues without a new attempt, which 3.x could not do.
/// Recipes (Bigo, FC2, niconico) open their own grant per attempt. Other
/// schemes (RTMP, RTSP, files) go to FFmpeg directly.
///
/// The relay this opener starts keeps a retained window of every HLS media
/// playlist and downloads its segments ahead of FFmpeg ([hlsPrefetch], 3.x's
/// recording prefetch; M8.1), so a slow CDN or a short live window no longer
/// costs segments.
final class RecordInputOpener {
  /// Creates an opener. [relay] returns the relay the app shares (or one this
  /// opener starts with [proxy] on first need and stops in [close]).
  new({
    this.proxy = const FixedProxyPolicy(),
    this.recipes = const [],
    this.hlsPrefetch = const HlsPrefetchOptions(),
    Future<LoopbackRelay> Function()? relay,
  }) : _startRelay = relay;

  /// Proxy routes for direct inputs and a relay this opener starts.
  final ProxyPolicy proxy;

  /// Openers of input recipes.
  final List<RecipeOpener> recipes;

  /// HLS prefetch of the relay this opener starts; null fetches on demand.
  final HlsPrefetchOptions? hlsPrefetch;

  final Future<LoopbackRelay> Function()? _startRelay;
  Future<LoopbackRelay>? _relay;
  late final MediaOpener _media = MediaOpener(proxy: proxy, recipes: recipes, relay: _relayNow);

  Future<LoopbackRelay> _relayNow() =>
      _relay ??= (_startRelay ?? () => LoopbackRelay.start(proxy: proxy, hlsPrefetch: hlsPrefetch)).call();

  /// Opens [stream] of platform [site]. [renew] fetches a fresh line for a
  /// lease that cuts the connection.
  Future<MediaInput> open(
    ResolvedRecordStream stream, {
    required String site,
    LineRenewer? renew,
    void Function(LivePlayLine line)? onRenewed,
    CancelToken? cancel,
  }) async {
    final source = stream.source;
    if (source is! LineSource) return await _media.open(source, site: site, cancel: cancel);
    final line = source.line;
    final route = MediaRoute.of(
      line,
      engine: const EngineProfile(),
      canRenew: renew != null,
      queryPolicy: stream.queryPolicy,
    );
    if (route != MediaRoute.direct) {
      return await _media.open(
        source,
        site: site,
        renew: renew,
        queryPolicy: stream.queryPolicy,
        onRenewed: onRenewed,
        cancel: cancel,
      );
    }
    final format = line.format ?? _formatOf(line.url);
    final scheme = Uri.tryParse(line.url)?.scheme.toLowerCase() ?? '';
    if ((scheme == 'http' || scheme == 'https') && (format == StreamFormat.flv || format == StreamFormat.hls)) {
      final relay = await _relayNow();
      final input = format == StreamFormat.flv ? relay.openFlv(line, site: site) : relay.openHls(line, site: site);
      return _RecordRelayInput(source, input);
    }
    return await _media.open(source, site: site, cancel: cancel);
  }

  /// Stops a relay this opener started.
  Future<void> close() async {
    final relay = _relay;
    _relay = null;
    if (relay != null && _startRelay == null) await (await relay).close();
  }

  static StreamFormat? _formatOf(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    if (path.endsWith('.flv')) return StreamFormat.flv;
    if (path.endsWith('.m3u8')) return StreamFormat.hls;
    return null;
  }
}

final class _RecordRelayInput implements MediaInput {
  new(this.source, this._input);

  @override
  final PlaybackSource source;
  final RelayInput _input;

  @override
  MediaRoute get route => MediaRoute.direct;

  @override
  Uri get uri => _input.uri;

  @override
  Map<String, String> get headers => const {};

  @override
  bool get private => true;

  @override
  String get proxyUrl => '';

  @override
  bool get onDemand => false;

  @override
  Duration? get start => null;

  @override
  LivePlayLine get line => _input.line;

  @override
  bool get isUsable => !_input.isClosed;

  @override
  Future<void> close() => _input.close();
}
