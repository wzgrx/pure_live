import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_media/src/relay/flv_splicer.dart';
import 'package:live_media/src/relay/hls_relay.dart';
import 'package:live_media/src/relay/hls_window.dart';
import 'package:live_media/src/relay/upstream.dart';
import 'package:live_net/live_net.dart';

/// A relayed input served on the loopback relay.
abstract interface class RelayInput {
  /// The loopback URL the engine opens.
  Uri get uri;

  /// The line the relay currently streams (changes on each renewal).
  LivePlayLine get line;

  /// Whether the input still serves.
  bool get isClosed;

  /// Renews an HLS line's lease now (see [HlsRoute.renewNow]); false when
  /// the input does not renew that way (FLV splices renew per connection).
  Future<bool> renewNow();

  /// Stops serving; open downstream connections end.
  Future<void> close();
}

/// A loopback HTTP server for relayed inputs (archive v4's `LoopbackRelay`;
/// 3.x started one server per relay): bound to 127.0.0.1 only, one random
/// unguessable path per input that stops working when the input closes.
/// Playback and recording can share it. Upstream requests go out with TLS
/// verification ([MediaTlsExemptions] aside) and the [proxy] policy's route.
final class LoopbackRelay {
  new _(this._server, this.proxy, this._opener, this._hlsUpstream, this.timings, {this.hlsPrefetch});

  /// Starts a relay on an ephemeral loopback port. [opener] and
  /// [hlsUpstream] replace the HTTP upstreams (tests); by default
  /// [openHttpFlv] and [IoHlsUpstream] with [proxy]'s route and
  /// [idleTimeout]. With [hlsPrefetch] every HLS input keeps a retained
  /// window and prefetches its segments (recording, M8.1).
  static Future<LoopbackRelay> start({
    ProxyPolicy proxy = const FixedProxyPolicy(),
    Duration idleTimeout = const Duration(seconds: 15),
    SpliceTimings timings = const SpliceTimings(),
    MediaTlsExemptions tls = MediaTlsExemptions.known,
    FlvSourceOpener Function(String site, {required bool rewriteLegacyHevc})? opener,
    HlsUpstream Function(String site)? hlsUpstream,
    HlsPrefetchOptions? hlsPrefetch,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = LoopbackRelay._(
      server,
      proxy,
      opener ??
          (site, {required rewriteLegacyHevc}) =>
              (line) => openHttpFlv(
                line,
                proxyDirective: proxy.routeFor(site, Uri.parse(line.url)).directive,
                connectTimeout: timings.connectTimeout,
                idleTimeout: idleTimeout,
                tls: tls,
                rewriteLegacyHevc: rewriteLegacyHevc,
              ),
      hlsUpstream ??
          (site) => IoHlsUpstream(
            site: site,
            proxy: proxy,
            connectTimeout: timings.connectTimeout,
            idleTimeout: idleTimeout,
            tls: tls,
          ),
      timings,
      hlsPrefetch: hlsPrefetch,
    );
    relay._requests = server.listen(relay._handle);
    return relay;
  }

  final HttpServer _server;

  /// Upstream proxy policy.
  final ProxyPolicy proxy;
  final FlvSourceOpener Function(String site, {required bool rewriteLegacyHevc}) _opener;
  final HlsUpstream Function(String site) _hlsUpstream;

  /// Splice limits.
  final SpliceTimings timings;

  /// Prefetch of the HLS inputs; null serves them on demand.
  final HlsPrefetchOptions? hlsPrefetch;
  late final StreamSubscription<HttpRequest> _requests;
  final _routes = <String, _FlvRoute>{};
  final _hlsRoutes = <String, _HlsInput>{};
  final _random = Random.secure();
  var _closed = false;

  /// Loopback port.
  int get port => _server.port;

  /// Whether [close] ran.
  bool get isClosed => _closed;

  /// Serves the FLV [line] as one continuous stream. With [renew], a lease
  /// that cuts the connection is renewed and spliced in ([FlvSplicer]);
  /// without, the stream is forwarded and ends with its upstream. With
  /// [rewriteLegacyHevc], codec-id-12 HEVC is rewritten to Enhanced FLV.
  /// Every engine request opens its own upstream connection (3.x). [site]
  /// selects the upstream proxy route; [onEvent] receives splice events and
  /// [onRenewed] each line switched to.
  RelayInput openFlv(
    LivePlayLine line, {
    required String site,
    LineRenewer? renew,
    bool rewriteLegacyHevc = false,
    void Function(SpliceEvent event)? onEvent,
    void Function(LivePlayLine line)? onRenewed,
  }) {
    if (_closed) throw StateError('LoopbackRelay is closed');
    final path = '/${_secret()}/live.flv';
    final route = _FlvRoute(
      relay: this,
      path: path,
      line: line,
      opener: _opener(site, rewriteLegacyHevc: rewriteLegacyHevc),
      renew: renew ?? (_) => Future.error(StateError('This FLV input is not renewed')),
      onEvent: onEvent,
      onRenewed: onRenewed,
    );
    _routes[path] = route;
    return route;
  }

  /// Serves the HLS [line] through [recipe] ([HlsRoute]); [renew] renews a
  /// lease that cuts the connection. [site] selects the upstream proxy route.
  RelayInput openHls(
    LivePlayLine line, {
    required String site,
    HlsRelayRecipe recipe = const HlsRelayRecipe(),
    HlsLineRenewer? renew,
  }) {
    if (_closed) throw StateError('LoopbackRelay is closed');
    final secret = _secret();
    final input = _HlsInput(
      this,
      secret,
      HlsRoute(
        prefix: '/$secret/',
        port: port,
        line: line,
        upstream: _hlsUpstream(site),
        recipe: recipe,
        renew: renew,
        prefetch: hlsPrefetch,
      ),
    );
    _hlsRoutes[secret] = input;
    return input;
  }

  String _secret() => base64UrlEncode(List.generate(18, (_) => _random.nextInt(256))).replaceAll('=', '');

  Future<void> _handle(HttpRequest request) async {
    final segments = request.uri.pathSegments;
    final hls = segments.length == 2 ? _hlsRoutes[segments.first] : null;
    if (!_closed && hls != null) {
      await hls.route.serve(request, segments.last);
      return;
    }
    final route = _routes[request.uri.path];
    if (_closed || route == null || request.method != 'GET') {
      try {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      } on Object {
        // The peer went away.
      }
      return;
    }
    await route.serve(request);
  }

  /// Stops the server and every input.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Future.wait([
      for (final route in _routes.values.toList()) route.close(),
      for (final input in _hlsRoutes.values.toList()) input.close(),
    ]);
    await _requests.cancel();
    await _server.close(force: true);
  }
}

final class _FlvRoute implements RelayInput {
  new({
    required this.relay,
    required this.path,
    required this._line,
    required this.opener,
    required this.renew,
    this.onEvent,
    this.onRenewed,
  });

  final LoopbackRelay relay;
  final String path;
  final FlvSourceOpener opener;
  final LineRenewer renew;
  final void Function(SpliceEvent event)? onEvent;
  final void Function(LivePlayLine line)? onRenewed;
  final _splicers = <FlvSplicer>{};
  LivePlayLine _line;
  Future<LivePlayLine>? _renewing;
  var _closed = false;

  @override
  LivePlayLine get line => _line;

  @override
  bool get isClosed => _closed || relay.isClosed;

  @override
  Uri get uri => Uri(scheme: 'http', host: '127.0.0.1', port: relay.port, path: path);

  /// Concurrent engine connections (a reconnect overlapping the old one)
  /// share one renewal per lease.
  Future<LivePlayLine> _renewShared(LivePlayLine current) {
    if (!identical(current, _line) && current.url != _line.url) return Future.value(_line);
    return _renewing ??= renew(current).whenComplete(() => _renewing = null);
  }

  Future<void> serve(HttpRequest request) async {
    final response = request.response;
    var started = false;
    final splicer = FlvSplicer(
      line: _line,
      open: opener,
      renew: _renewShared,
      emit: (packet) {
        if (!started) {
          started = true;
          response
            ..statusCode = HttpStatus.ok
            ..bufferOutput = false
            ..headers.contentType = ContentType('video', 'x-flv')
            ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
        }
        response.add(packet);
      },
      onEvent: (event) {
        if (event is SpliceSwitched) {
          _line = event.line;
          onRenewed?.call(event.line);
        }
        onEvent?.call(event);
      },
      timings: relay.timings,
    );
    _splicers.add(splicer);
    // The player hanging up ends this splicer.
    unawaited(response.done.then((_) {}, onError: (Object _) {}).whenComplete(splicer.cancel));
    try {
      await splicer.run();
    } on Object catch (error) {
      onEvent?.call(SpliceEnded('upstream failed: $error'));
      if (!started) {
        try {
          response.statusCode = HttpStatus.badGateway;
        } on Object {
          // Headers already sent.
        }
      }
    } finally {
      _splicers.remove(splicer);
      try {
        await response.close();
      } on Object {
        // The player already went away.
      }
    }
  }

  @override
  Future<bool> renewNow() async => false;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    relay._routes.remove(path);
    await Future.wait([for (final splicer in _splicers.toList()) splicer.cancel()]);
  }
}

final class _HlsInput implements RelayInput {
  new(this.relay, this.secret, this.route);

  final LoopbackRelay relay;
  final String secret;
  final HlsRoute route;
  var _closed = false;

  @override
  Uri get uri => route.uri;

  @override
  LivePlayLine get line => route.line;

  @override
  bool get isClosed => _closed || relay.isClosed;

  @override
  Future<bool> renewNow() => route.renewNow();

  @override
  Future<void> close() async {
    _closed = true;
    relay._hlsRoutes.remove(secret);
    route.close();
  }
}
