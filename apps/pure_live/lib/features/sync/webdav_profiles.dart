import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:live_store/live_store.dart';

/// A WebDAV account (store.md §10): name (unique), base URL, user name,
/// remote directory. The password lives in the secret store under
/// `webdav/<id>`, never here.
@immutable
final class WebDavProfile {
  /// Creates a profile.
  const new({required this.id, required this.name, required this.baseUrl, this.username = '', this.remoteDir = ''});

  /// Reads a stored profile; null for a malformed entry.
  static WebDavProfile? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final id = json['id'];
    final name = json['name'];
    final baseUrl = json['baseUrl'];
    if (id is! String || id.isEmpty || name is! String || baseUrl is! String) return null;
    return WebDavProfile(
      id: id,
      name: name,
      baseUrl: baseUrl,
      username: json['username'] is String ? json['username']! as String : '',
      remoteDir: json['remoteDir'] is String ? json['remoteDir']! as String : '',
    );
  }

  /// Stable id; the secret reference is derived from it.
  final String id;

  /// Display name, unique ignoring case.
  final String name;

  /// Server URL of the WebDAV root, for example `https://dav.jianguoyun.com/dav/`.
  final String baseUrl;

  /// User name.
  final String username;

  /// Directory for backups below [baseUrl], `/`-separated; empty is the root.
  final String remoteDir;

  /// [remoteDir] as path segments.
  List<String> get directory => splitDirectory(remoteDir);

  /// [baseUrl] parsed.
  Uri get base => Uri.parse(baseUrl.trim());

  /// Secret reference of the password.
  String get secretRef => SecretRefs.webdav(id);

  /// JSON for the meta table.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'username': username,
    'remoteDir': remoteDir,
  };

  /// A copy with the given fields replaced.
  WebDavProfile copyWith({String? name, String? baseUrl, String? username, String? remoteDir}) => WebDavProfile(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    username: username ?? this.username,
    remoteDir: remoteDir ?? this.remoteDir,
  );

  /// Splits a `/`-separated directory into segments.
  static List<String> splitDirectory(String directory) => [
    for (final segment in directory.split(RegExp(r'[/\\]')))
      if (segment.trim().isNotEmpty) segment.trim(),
  ];

  /// Whether [address] is a usable base URL (store.md §6.4.12, 3.x rules):
  /// http or https, a host, no user info, no query or fragment.
  static bool isValidUrl(String address) {
    final value = address.trim();
    if (value.isEmpty || RegExp(r'[\x00-\x1f\x7f\\]').hasMatch(value)) return false;
    if (RegExp('^https?://[^/?#]*@', caseSensitive: false).hasMatch(value)) return false;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    return !RegExp(r'[\s/\\?#@]').hasMatch(uri.host) && uri.port > 0 && uri.port <= 65535;
  }

  @override
  String toString() => 'WebDavProfile($id, $name)';
}

/// Why a profile could not be saved.
enum WebDavProfileError {
  /// The name is empty.
  emptyName,

  /// Another profile has this name.
  duplicateName,

  /// The URL is not a usable WebDAV base URL.
  invalidUrl,
}

/// Thrown by [WebDavProfileStore.save].
final class WebDavProfileException implements Exception {
  /// Creates the exception.
  const new(this.error);

  /// What is wrong.
  final WebDavProfileError error;

  @override
  String toString() => 'WebDavProfileException(${error.name})';
}

/// WebDAV profiles in the meta table (the v4.0 database has no
/// `webdav_profiles` table yet, ADR 0017 §1), passwords in the secret store.
final class WebDavProfileStore {
  /// Uses [_meta] and [_secrets].
  new(this._meta, this._secrets);

  final MetaStore _meta;
  final SecretStore _secrets;

  /// Meta key of the profile list.
  static const profilesKey = 'webdav.profiles';

  /// Meta key of the current profile's id.
  static const currentKey = 'webdav.current';

  /// Every profile in the order they were added.
  Future<List<WebDavProfile>> load() async {
    final text = await _meta.get(profilesKey);
    if (text == null) return [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List<Object?>) return [];
      return [...decoded.map(WebDavProfile.fromJson).nonNulls];
    } on FormatException {
      return [];
    }
  }

  /// Id of the profile the WebDAV page opens with.
  Future<String?> currentId() => _meta.get(currentKey);

  /// Makes [id] the current profile.
  Future<void> setCurrent(String? id) => _meta.set(currentKey, id);

  /// The stored password of [profile], or an empty string.
  String passwordOf(WebDavProfile profile) => _secrets.read(profile.secretRef) ?? '';

  /// Adds or replaces [profile]; a non-null [password] replaces the stored
  /// one (empty removes it). Throws [WebDavProfileException].
  Future<WebDavProfile> save(WebDavProfile profile, {String? password}) async {
    final name = profile.name.trim();
    if (name.isEmpty) throw const WebDavProfileException(WebDavProfileError.emptyName);
    if (!WebDavProfile.isValidUrl(profile.baseUrl)) throw const WebDavProfileException(WebDavProfileError.invalidUrl);
    final profiles = await load();
    if (profiles.any((other) => other.id != profile.id && other.name.trim().toLowerCase() == name.toLowerCase())) {
      throw const WebDavProfileException(WebDavProfileError.duplicateName);
    }
    final saved = profile.copyWith(
      name: name,
      baseUrl: profile.baseUrl.trim(),
      username: profile.username.trim(),
      remoteDir: WebDavProfile.splitDirectory(profile.remoteDir).join('/'),
    );
    final index = profiles.indexWhere((other) => other.id == profile.id);
    if (index < 0) {
      profiles.add(saved);
    } else {
      profiles[index] = saved;
    }
    if (password != null) await _secrets.write(saved.secretRef, password);
    await _meta.set(profilesKey, jsonEncode([for (final item in profiles) item.toJson()]));
    return saved;
  }

  /// Removes the profile [id] and its password.
  Future<void> delete(String id) async {
    final profiles = await load();
    profiles.removeWhere((profile) => profile.id == id);
    await _meta.set(profilesKey, jsonEncode([for (final item in profiles) item.toJson()]));
    await _secrets.write(SecretRefs.webdav(id), null);
    if (await currentId() == id) await setCurrent(profiles.isEmpty ? null : profiles.first.id);
  }

  /// A new random profile id.
  static String newId() {
    final random = Random.secure();
    return List.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();
  }
}
