import 'package:meta/meta.dart';

/// How requests for one platform reach the network (ADR 0011, rule 3).
@immutable
sealed class ProxyRoute {
  const new();

  /// `HttpClient.findProxy` directive for this route.
  String get directive;
}

/// No proxy.
final class DirectRoute extends ProxyRoute {
  /// Creates the route.
  const new();

  @override
  String get directive => 'DIRECT';

  @override
  bool operator ==(Object other) => other is DirectRoute;

  @override
  int get hashCode => 0;
}

/// An HTTP proxy (CONNECT for https).
final class HttpProxyRoute extends ProxyRoute {
  /// Creates the route.
  const new(this.host, this.port);

  /// Proxy host.
  final String host;

  /// Proxy port.
  final int port;

  @override
  String get directive => 'PROXY $host:$port';

  @override
  bool operator ==(Object other) => other is HttpProxyRoute && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

/// Picks the route per platform; injected by the app from its settings.
abstract interface class ProxyPolicy {
  /// Route for [site]'s request to [url].
  ProxyRoute routeFor(String site, Uri url);
}

/// A global route with per-platform overrides.
final class FixedProxyPolicy implements ProxyPolicy {
  /// Creates the policy.
  const new({this.global = const DirectRoute(), this.perSite = const {}});

  /// Route for platforms without an override.
  final ProxyRoute global;

  /// Overrides by platform id.
  final Map<String, ProxyRoute> perSite;

  @override
  ProxyRoute routeFor(String site, Uri url) => perSite[site] ?? global;
}
