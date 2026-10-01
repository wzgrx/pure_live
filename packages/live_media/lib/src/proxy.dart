import 'package:live_net/live_net.dart';

/// The engine's own proxy for a media URL (3.x's `PlaybackProxyPolicy`):
/// mpv's `http-proxy` value.
///
/// 3.x read the global proxy settings and ignored the per-platform routes the
/// API requests used; here the route comes from the same [ProxyPolicy] as
/// the platform's requests. A loopback input ([private]) is never proxied:
/// the relay already went through the route upstream.
String engineProxyUrl(ProxyPolicy policy, String site, Uri media, {bool private = false}) {
  if (private) return '';
  return switch (policy.routeFor(site, media)) {
    DirectRoute() => '',
    final HttpProxyRoute route => 'http://${route.host.contains(':') ? '[${route.host}]' : route.host}:${route.port}',
  };
}
