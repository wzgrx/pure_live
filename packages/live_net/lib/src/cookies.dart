import 'dart:async';

/// The user's stored credentials per platform. The app
/// implements it on its encrypted store; adapters never cache the value
/// beyond a [changes] notification.
abstract interface class CookieVault {
  /// The user's cookie header for [site], or null when signed out.
  String? cookieFor(String site);

  /// Emits a platform id whenever its credentials change.
  Stream<String> get changes;
}

/// A vault held in memory, for tests and the command-line tools.
final class MemoryCookieVault implements CookieVault {
  final Map<String, String> _cookies = {};
  final StreamController<String> _changes = StreamController<String>.broadcast();

  @override
  String? cookieFor(String site) => _cookies[site];

  @override
  Stream<String> get changes => _changes.stream;

  /// Stores [cookie] for [site]; null signs out.
  void set(String site, String? cookie) {
    if (cookie == null || cookie.trim().isEmpty) {
      if (_cookies.remove(site) == null) return;
    } else {
      if (_cookies[site] == cookie) return;
      _cookies[site] = cookie;
    }
    _changes.add(site);
  }

  /// Closes the change stream.
  Future<void> dispose() => _changes.close();
}
