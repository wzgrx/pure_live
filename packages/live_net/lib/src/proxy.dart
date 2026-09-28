import 'package:meta/meta.dart';

/// How requests for one platform reach the network.
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
  /// Creates the route; [host] is written without brackets.
  const new(this.host, this.port);

  /// Proxy host.
  final String host;

  /// Proxy port.
  final int port;

  /// IPv6 hosts are bracketed so `dart:io` can split host and port.
  @override
  String get directive => 'PROXY ${host.contains(':') ? '[$host]' : host}:$port';

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

/// Port used when a stored port is invalid (3.x's default, a local Clash).
const int defaultProxyPort = 7897;

/// Whether [port] is a usable TCP port.
bool isValidProxyPort(int port) => port >= 1 && port <= 65535;

/// Repairs a stored or imported port instead of passing an invalid socket
/// endpoint to every request, the player and the recorder.
int normalizeStoredProxyPort(int port) => isValidProxyPort(port) ? port : defaultProxyPort;

/// A usable port from a settings field being edited, else null: an empty,
/// partial or out-of-range value stays in the field for the user to finish
/// but must not replace the last working port.
int? parseProxyPortInput(String value) {
  final port = int.tryParse(value.trim());
  return port != null && isValidProxyPort(port) ? port : null;
}

/// A proxy host as typed on a phone or PC, repaired.
///
/// Chinese input methods turn an ASCII dot into `。` or `．`. Passed to
/// `findProxy`, Android tries to resolve the whole string as a DNS name and a
/// valid `127.0.0.1` proxy silently breaks every request.
String normalizeProxyHost(String value) => value
    .trim()
    .replaceAll('。', '.')
    .replaceAll('．', '.')
    .replaceAll('：', ':')
    .replaceAll('［', '[')
    .replaceAll('］', ']')
    .replaceAll(RegExp(r'\s+'), '');

/// The route for the proxy settings: [enabled], [host] as typed and [port].
///
/// Disabled, empty, half-edited or invalid values stay direct, so an
/// unfinished settings field never turns every request into a failed proxy
/// lookup. A host carrying `;` or a line break could inject a second
/// directive and is rejected.
ProxyRoute proxyRouteFrom({required bool enabled, required String host, required int port}) {
  if (!enabled || host.contains(';') || host.contains('\r') || host.contains('\n')) return const DirectRoute();
  var normalized = normalizeProxyHost(host);
  if (normalized.startsWith('[') && normalized.endsWith(']')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  if (normalized.isEmpty || !isValidProxyPort(port)) return const DirectRoute();
  return HttpProxyRoute(normalized, port);
}

/// Whether a proxy host is on the local network (a Clash on the PC, a soft
/// router). Android 17 gates such hosts behind `ACCESS_LOCAL_NETWORK` for
/// apps targeting API 37; loopback is the device itself and is not gated.
bool isLocalNetworkProxyHost(String value) {
  var host = normalizeProxyHost(value).toLowerCase();
  if (host.startsWith('[') && host.endsWith(']')) host = host.substring(1, host.length - 1);
  if (host.isEmpty) return false;
  if (host.endsWith('.local') || host.endsWith('.lan') || host.endsWith('.home.arpa')) return true;
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(host);
  if (v4 != null) {
    final octets = [for (var i = 1; i <= 4; i++) int.parse(v4.group(i)!)];
    if (octets.any((octet) => octet > 255)) return false;
    final [a, b, _, _] = octets;
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
  }
  if (host.contains(':')) {
    // IPv6 unique-local (fc00::/7) and link-local (fe80::/10).
    return RegExp('^f[cd][0-9a-f]{0,2}:').hasMatch(host) || RegExp('^fe[89ab][0-9a-f]?:').hasMatch(host);
  }
  return false;
}
