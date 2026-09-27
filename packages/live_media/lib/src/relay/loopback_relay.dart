import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_media/src/relay/flv_splicer.dart';
import 'package:live_media/src/relay/upstream.dart';
import 'package:live_net/live_net.dart';

/// A relayed input served on the loopback relay.
abstract interface class RelayInput {
  /// The loopback URL the engine opens.
  Uri get uri;

  /// The line the relay currently streams (changes on each renewal).
  StreamLine get line;

  /// Stops serving; open downstream connections end.
  Future<void> close();
}

/// A loopback HTTP server for relayed inputs (SRC-4): bound to 127.0.0.1
/// only, one random unguessable path per input that stops working when the
/// input closes. Playback and recording share it. Upstream requests go out
/// with TLS verification and the [proxy] policy's route.
final class LoopbackRelay {
  new _(this._server, this.proxy, this._opener, this.timings);

  /// Starts a relay on an ephemeral loopback port. [opener] replaces the
  /// HTTP upstream (tests); by default [openHttpFlv] with [proxy]'s route
  /// and [idleTimeout].
  static Future<LoopbackRelay> start({
    ProxyPolicy proxy = const FixedProxyPolicy(),
    Duration idleTimeout = const Duration(seconds: 15),
    SpliceTimings timings = const SpliceTimings(),
    FlvSourceOpener Function(String site)? opener,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = LoopbackRelay._(
      server,
      proxy,
      opener ??
          (site) =>
              (line) => openHttpFlv(
                line,
                proxyDirective: proxy.routeFor(site, line.url).directive,
                connectTimeout: timings.connectTimeout,
                idleTimeout: idleTimeout,
              ),
      timings,
    );
    relay._requests = server.listen(relay._handle);
    return relay;
  }

  final HttpServer _server;

  /// Upstream proxy policy.
  final ProxyPolicy proxy;
  final FlvSourceOpener Function(String site) _opener;

  /// Splice limits.
  final SpliceTimings timings;
  late final StreamSubscription<HttpRequest> _requests;
  final _routes = <String, _SpliceRoute>{};
  final _random = Random.secure();
  var _closed = false;

  /// Loopback port.
  int get port => _server.port;

  /// Whether [close] ran.
  bool get isClosed => _closed;

  /// Serves [line] as one continuous FLV, renewing it through [renew] at each
  /// lease (SRC-5). [site] selects the upstream proxy route; [onEvent]
  /// receives splice events and [onRenewed] each line switched to.
  RelayInput openSplice(
    StreamLine line, {
    required String site,
    required LineRenewer renew,
    void Function(SpliceEvent event)? onEvent,
    void Function(StreamLine line)? onRenewed,
  }) {
    if (_closed) throw StateError('LoopbackRelay is closed');
    final secret = base64UrlEncode(List.generate(18, (_) => _random.nextInt(256))).replaceAll('=', '');
    final path = '/$secret/live.flv';
    final route = _SpliceRoute(
      relay: this,
      path: path,
      line: line,
      opener: _opener(site),
      renew: renew,
      onEvent: onEvent,
      onRenewed: onRenewed,
    );
    _routes[path] = route;
    return route;
  }

  Future<void> _handle(HttpRequest request) async {
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
    await Future.wait([for (final route in _routes.values.toList()) route.close()]);
    await _requests.cancel();
    await _server.close(force: true);
  }
}

final class _SpliceRoute implements RelayInput {
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
  final void Function(StreamLine line)? onRenewed;
  final _splicers = <FlvSplicer>{};
  StreamLine _line;
  Future<StreamLine>? _renewing;
  var _closed = false;

  @override
  StreamLine get line => _line;

  @override
  Uri get uri => Uri(scheme: 'http', host: '127.0.0.1', port: relay.port, path: path);

  /// Concurrent downstream connections (a reconnect overlapping the old one)
  /// share one renewal per lease.
  Future<StreamLine> _renewShared(StreamLine current) {
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
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    relay._routes.remove(path);
    await Future.wait([for (final splicer in _splicers.toList()) splicer.cancel()]);
  }
}
