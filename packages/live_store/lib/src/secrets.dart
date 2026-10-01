import 'dart:async';
import 'dart:typed_data';

import 'package:live_store/src/database.dart';

/// Encrypts secrets for this device: Android Keystore or Windows DPAPI,
/// provided by the app (M12). The key never leaves the platform, so the
/// interface seals and opens instead of handing out a key.
abstract interface class SecretCipher {
  /// [plain] encrypted; [ref] is bound to the result so a sealed value
  /// cannot be moved to another name.
  Future<Uint8List> seal(String ref, String plain);

  /// The plain text of [sealed]; throws when it cannot be opened (another
  /// device, a reinstall, a lost key).
  Future<String> open(String ref, Uint8List sealed);
}

/// Names of the stored secrets.
abstract final class SecretRefs {
  /// The cookie of platform [site] (3.x `<site>Cookie`).
  static String cookie(String site) => 'cookie/${site.trim().toLowerCase()}';

  /// Douyu's long-term passport key (3.x `douyuLtp0`).
  static const douyuLtp0 = 'cookie/douyu.ltp0';

  /// Douyu's passport device id (3.x `douyuDid`).
  static const douyuDid = 'cookie/douyu.did';

  /// The password of WebDAV server [name].
  static String webdav(String name) => 'webdav/$name';

  static const _cookiePrefix = 'cookie/';
}

final RegExp _controlCharacters = RegExp(r'[\u0000-\u001F\u007F]');

/// A cookie header as pasted or stored, with control characters removed and
/// trimmed (3.x `normalizeAccountCookie`).
String normalizeCookie(String value) => value.replaceAll(_controlCharacters, '').trim();

/// Cookies and passwords, sealed by a [SecretCipher] in the database (3.x
/// kept them in plain text in the settings box).
///
/// Everything is opened when the store loads, so [cookieFor] is synchronous
/// and the app can implement live_net's `CookieVault` with
/// `cookieFor: secrets.cookieFor, changes: secrets.cookieChanges`. A value
/// that cannot be opened is treated as signed out and listed in
/// [unreadable]; its sealed bytes stay until the name is written again.
final class SecretStore {
  new _(this._db, this._cipher, this._values, this.unreadable);

  /// Opens every stored secret with [cipher].
  static Future<SecretStore> load(StoreDatabase db, SecretCipher cipher) async {
    final values = <String, String>{};
    final unreadable = <String>{};
    for (final row in await db.rows('SELECT ref, sealed FROM secrets')) {
      final ref = row.read<String>('ref');
      try {
        values[ref] = await cipher.open(ref, row.read<Uint8List>('sealed'));
      } on Object {
        unreadable.add(ref);
      }
    }
    return SecretStore._(db, cipher, values, unreadable);
  }

  final StoreDatabase _db;
  final SecretCipher _cipher;
  final Map<String, String> _values;
  final StreamController<String> _changes = StreamController.broadcast();

  /// Names whose sealed value could not be opened.
  final Set<String> unreadable;

  /// The secret [ref], or null.
  String? read(String ref) => _values[ref];

  /// The cookie header of [site], or null when signed out.
  String? cookieFor(String site) => _values[SecretRefs.cookie(site)];

  /// Platforms with a stored cookie.
  Set<String> get cookieSites => {
    for (final ref in _values.keys)
      if (ref.startsWith(SecretRefs._cookiePrefix) && !ref.contains('.'))
        ref.substring(SecretRefs._cookiePrefix.length),
  };

  /// Stores [value] under [ref]; null or empty removes it.
  Future<void> write(String ref, String? value) => writeAll({ref: value});

  /// Stores several secrets in one transaction.
  Future<void> writeAll(Map<String, String?> values) async {
    final sealed = <String, Uint8List?>{
      for (final entry in values.entries)
        entry.key: entry.value == null || entry.value!.isEmpty ? null : await _cipher.seal(entry.key, entry.value!),
    };
    await _db.write({StoreTables.secrets}, () async {
      for (final entry in sealed.entries) {
        if (entry.value case final bytes?) {
          await _db.run('INSERT OR REPLACE INTO secrets (ref, sealed) VALUES (?, ?)', [entry.key, bytes]);
        } else {
          await _db.run('DELETE FROM secrets WHERE ref = ?', [entry.key]);
        }
      }
    });
    for (final entry in values.entries) {
      final value = entry.value;
      final before = _values[entry.key];
      if (value == null || value.isEmpty) {
        _values.remove(entry.key);
      } else {
        _values[entry.key] = value;
      }
      unreadable.remove(entry.key);
      if (before != _values[entry.key]) _changes.add(entry.key);
    }
  }

  /// Stores the cookie of [site], normalised; empty signs out.
  Future<void> setCookie(String site, String cookie) => write(SecretRefs.cookie(site), normalizeCookie(cookie));

  /// Removes every cookie (3.x `clearAllCookies`).
  Future<void> clearCookies() => writeAll({
    for (final ref in {..._values.keys, ...unreadable})
      if (ref.startsWith(SecretRefs._cookiePrefix)) ref: null,
  });

  /// Names of changed secrets.
  Stream<String> get changes => _changes.stream;

  /// Platforms whose cookie changed (for live_net's `CookieVault.changes`).
  Stream<String> get cookieChanges => changes
      .where((ref) => ref.startsWith(SecretRefs._cookiePrefix))
      .map((ref) => ref.substring(SecretRefs._cookiePrefix.length).split('.').first);

  /// Closes [changes].
  Future<void> close() => _changes.close();
}
