import 'dart:io';

/// Bounded in-memory cookies of one HLS relay, never an account jar (3.x's
/// `HlsSessionCookies`).
///
/// Cookies are pinned to the issuing origin even when they name a parent
/// domain: a playlist may point at any CDN host, and one host must not get
/// another's session. TwitCasting's segments need the `lvhls_ssid_{movie}`
/// cookie its media playlist sets (REG-TWITCASTING-002).
final class HlsSessionCookies {
  /// Creates an empty jar; [now] is injectable for tests.
  new({DateTime Function()? now}) : _now = now ?? DateTime.now;

  /// Most cookies kept.
  static const int maximumCount = 64;

  /// Most characters kept in all.
  static const int maximumCharacters = 16 * 1024;

  /// Longest single cookie accepted.
  static const int maximumCookieCharacters = 4096;

  final DateTime Function() _now;
  final Map<(String, String, String), _SessionCookie> _cookies = {};
  int _sequence = 0;

  /// Cookies kept.
  int get count => _cookies.length;

  /// Characters kept.
  int get retainedCharacters => _cookies.values.fold(0, (sum, cookie) => sum + cookie.size);

  /// Drops every cookie.
  void clear() => _cookies.clear();

  /// Keeps the `Set-Cookie` [values] of an answer from [uri]. Malformed,
  /// foreign-domain, insecure-over-http and oversized cookies are ignored;
  /// an expired one removes its earlier value.
  void receive(Uri uri, Iterable<String> values) {
    final now = _now();
    _prune(now);
    for (final value in values) {
      if (value.length > maximumCookieCharacters) continue;
      final Cookie cookie;
      try {
        cookie = Cookie.fromSetCookieValue(value);
      } on Object {
        continue;
      }
      if (cookie.name.isEmpty) continue;
      var domain = cookie.domain?.toLowerCase();
      if (domain != null) {
        if (domain.startsWith('.')) domain = domain.substring(1);
        final exact = uri.host == domain;
        final parent = InternetAddress.tryParse(uri.host) == null && uri.host.endsWith('.$domain');
        if (domain.isEmpty || (!exact && !parent)) continue;
      }
      if (cookie.secure && uri.scheme != 'https') continue;
      if (cookie.name.startsWith('__Secure-') && (!cookie.secure || uri.scheme != 'https')) continue;
      if (cookie.name.startsWith('__Host-') &&
          (!cookie.secure || uri.scheme != 'https' || domain != null || cookie.path != '/')) {
        continue;
      }
      final path = (cookie.path?.startsWith('/') ?? false) ? cookie.path! : _defaultPath(uri.path);
      final key = (uri.origin, path, cookie.name);
      // Max-Age wins over Expires; lifetimes are capped at a year before
      // arithmetic.
      final maxAge = cookie.maxAge;
      final expires = maxAge == null ? cookie.expires : now.add(Duration(seconds: maxAge.clamp(0, 365 * 24 * 60 * 60)));
      final previous = _cookies.remove(key);
      if (expires != null && !expires.isAfter(now)) continue;
      final entry = _SessionCookie(
        origin: uri.origin,
        path: path,
        name: cookie.name,
        value: cookie.value,
        expires: expires,
        sequence: previous?.sequence ?? _sequence++,
      );
      if (entry.size > maximumCookieCharacters) continue;
      _cookies[key] = entry;
      while (_cookies.length > maximumCount || retainedCharacters > maximumCharacters) {
        _cookies.remove(_cookies.keys.first);
      }
    }
  }

  /// The `Cookie` header for [uri]: kept cookies of its origin whose path
  /// matches (longest path first, then oldest), then the pairs of
  /// [initialHeader] whose names were not set by the session; null when
  /// there are none.
  String? headerFor(Uri uri, {String? initialHeader}) {
    _prune(_now());
    final selected =
        _cookies.values.where((cookie) => cookie.origin == uri.origin && _pathMatches(uri.path, cookie.path)).toList()
          ..sort((a, b) {
            final byPath = b.path.length.compareTo(a.path.length);
            return byPath != 0 ? byPath : a.sequence.compareTo(b.sequence);
          });
    final names = {for (final cookie in selected) cookie.name};
    final initial = (initialHeader ?? '').split(';').map((pair) => pair.trim()).where((pair) {
      final separator = pair.indexOf('=');
      return separator > 0 && !names.contains(pair.substring(0, separator).trim());
    });
    final pairs = [for (final cookie in selected) '${cookie.name}=${cookie.value}', ...initial];
    return pairs.isEmpty ? null : pairs.join('; ');
  }

  void _prune(DateTime now) => _cookies.removeWhere((_, cookie) => !(cookie.expires?.isAfter(now) ?? true));

  static String _defaultPath(String path) {
    final lastSlash = path.lastIndexOf('/');
    return lastSlash <= 0 ? '/' : path.substring(0, lastSlash);
  }

  static bool _pathMatches(String request, String cookie) =>
      request == cookie ||
      (request.startsWith(cookie) && (cookie.endsWith('/') || request.substring(cookie.length).startsWith('/')));
}

final class _SessionCookie {
  const new({
    required this.origin,
    required this.path,
    required this.name,
    required this.value,
    required this.expires,
    required this.sequence,
  });

  final String origin;
  final String path;
  final String name;
  final String value;
  final DateTime? expires;
  final int sequence;

  int get size => origin.length + path.length + name.length + value.length;
}
