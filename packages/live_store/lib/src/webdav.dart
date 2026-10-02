import 'package:live_store/src/database.dart';
import 'package:live_store/src/secrets.dart';
import 'package:meta/meta.dart';

/// A WebDAV server (3.x `WebDAVConfig`); the password is a secret.
@immutable
final class WebDavConfig {
  /// Creates a server entry.
  const new({required this.name, required this.address, this.username = '', this.password = ''});

  /// Reads 3.x's `{name, address, username, password}`.
  factory fromJson(Map<String, Object?> json) => WebDavConfig(
    name: '${json['name'] ?? ''}',
    address: '${json['address'] ?? ''}',
    username: '${json['username'] ?? ''}',
    password: '${json['password'] ?? ''}',
  );

  /// Unique name.
  final String name;

  /// Base URL of the backup folder.
  final String address;

  /// User name.
  final String username;

  /// Password.
  final String password;

  /// 3.x's JSON; [withPassword] false leaves the password out.
  Map<String, Object?> toJson({bool withPassword = true}) => {
    'name': name,
    'address': address,
    'username': username,
    if (withPassword) 'password': password,
  };

  /// Whether [address] can be a base URL: http(s), a host, no user info,
  /// query or fragment, no control characters or backslashes (3.x
  /// `WebDAVConfig.isValidAddress`).
  static bool isValidAddress(String address) {
    final value = address.trim();
    if (value.isEmpty || RegExp(r'[\x00-\x1f\x7f\\]').hasMatch(value)) return false;
    if (RegExp('^https?://[^/?#]*@', caseSensitive: false).hasMatch(value)) return false;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.authority.contains('@') ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    final host = Uri.decodeComponent(uri.host);
    return !RegExp(r'[\s/\\?#@]').hasMatch(host) && uri.port > 0 && uri.port <= 65535;
  }

  @override
  bool operator ==(Object other) =>
      other is WebDavConfig &&
      other.name == name &&
      other.address == address &&
      other.username == username &&
      other.password == password;

  @override
  int get hashCode => Object.hash(name, address, username, password);

  @override
  String toString() => 'WebDavConfig($name, $address)';
}

/// WebDAV servers (3.x `WebDavController`); names are unique, passwords are
/// sealed in the [SecretStore], and the current server is kept by name (3.x
/// kept a second full copy, password included).
final class WebDavStore {
  /// Creates the store over `db` and `secrets`.
  new(this._db, this._secrets);

  final StoreDatabase _db;
  final SecretStore _secrets;

  static const _currentKey = 'webdav.current';
  static const Set<String> _tables = {StoreTables.webdav, StoreTables.meta};

  /// The servers, in order, with passwords.
  Future<List<WebDavConfig>> all() async => [
    for (final row in await _db.rows('SELECT name, address, username FROM webdav_profiles ORDER BY position, rowid'))
      WebDavConfig(
        name: row.read<String>('name'),
        address: row.read<String>('address'),
        username: row.read<String>('username'),
        password: _secrets.read(SecretRefs.webdav(row.read<String>('name'))) ?? '',
      ),
  ];

  /// [all], again after every change.
  Stream<List<WebDavConfig>> watchAll() => _db.watch(_tables, all);

  /// The current server, if any.
  Future<WebDavConfig?> current() async {
    final rows = await _db.rows('SELECT value FROM meta WHERE key = ?', [_currentKey]);
    if (rows.isEmpty) return null;
    final name = rows.single.read<String>('value');
    return (await all()).where((config) => config.name == name).firstOrNull;
  }

  /// Adds [config]; false when the name is taken.
  Future<bool> add(WebDavConfig config) async {
    final configs = await all();
    if (configs.any((c) => c.name == config.name)) return false;
    await replaceAll([...configs, config], current: await current());
    return true;
  }

  /// Replaces the server named like [config]; false when there is none.
  Future<bool> update(WebDavConfig config) async {
    final configs = await all();
    final index = configs.indexWhere((c) => c.name == config.name);
    if (index < 0) return false;
    configs[index] = config;
    await replaceAll(configs, current: await current());
    return true;
  }

  /// Removes server [name] and its password.
  Future<bool> remove(String name) async {
    final configs = await all();
    final kept = configs.where((c) => c.name != name).toList();
    if (kept.length == configs.length) return false;
    final selected = await current();
    await replaceAll(kept, current: selected?.name == name ? null : selected);
    return true;
  }

  /// Makes [name] the current server (null for none).
  Future<void> select(String? name) async => await replaceAll(
    await all(),
    current: name == null ? null : WebDavConfig(name: name, address: ''),
  );

  /// Replaces every server and the current one, in one transaction (3.x
  /// `replaceStateDurably`). Duplicate names keep the first; the current
  /// one is matched by name. [withPasswords] false leaves the stored
  /// passwords as they are (nothing is encrypted; a removed server's
  /// password still goes).
  Future<void> replaceAll(Iterable<WebDavConfig> configs, {WebDavConfig? current, bool withPasswords = true}) async {
    final unique = <String, WebDavConfig>{};
    for (final config in configs) {
      if (config.name.isNotEmpty) unique.putIfAbsent(config.name, () => config);
    }
    final previous = [for (final row in await _db.rows('SELECT name FROM webdav_profiles')) row.read<String>('name')];
    await _secrets.writeAll({
      for (final name in previous)
        if (!unique.containsKey(name)) SecretRefs.webdav(name): null,
      if (withPasswords)
        for (final config in unique.values) SecretRefs.webdav(config.name): config.password,
    });
    await _db.write(_tables, () async {
      await _db.run('DELETE FROM webdav_profiles');
      var position = 0;
      for (final config in unique.values) {
        await _db.run('INSERT INTO webdav_profiles (name, position, address, username) VALUES (?, ?, ?, ?)', [
          config.name,
          position++,
          config.address,
          config.username,
        ]);
      }
      final selected = current != null && unique.containsKey(current.name) ? current.name : null;
      if (selected == null) {
        await _db.run('DELETE FROM meta WHERE key = ?', [_currentKey]);
      } else {
        await _db.run('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', [_currentKey, selected]);
      }
    });
  }
}
