import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Prefix of an Xtream playlist or guide source (F-IPTV-07): `xtream:<id>`
/// for the playlist, `xtream:<id>#guide` for its guide. The server, user
/// name and password stay in the encrypted secret store; the database and
/// backups only ever see this reference.
const xtreamScheme = 'xtream:';

/// Whether [source] is an Xtream reference.
bool isXtreamSource(String source) => source.startsWith(xtreamScheme);

/// The account id of an Xtream [source].
String? xtreamIdOf(String source) {
  if (!isXtreamSource(source)) return null;
  final rest = source.substring(xtreamScheme.length);
  final id = rest.split('#').first;
  return id.isEmpty ? null : id;
}

/// An Xtream Codes account.
@immutable
final class XtreamAccount {
  const new({required this.server, required this.username, required this.password});

  /// Reads what the user typed; the scheme defaults to http and a trailing
  /// path or query is dropped. Null when the server is not a web address.
  static XtreamAccount? tryParse({required String server, required String username, required String password}) {
    final text = server.trim();
    final user = username.trim();
    if (text.isEmpty || user.isEmpty || password.isEmpty) return null;
    final uri = Uri.tryParse(text.contains('://') ? text : 'http://$text');
    if (uri == null || uri.host.isEmpty || !(uri.isScheme('http') || uri.isScheme('https'))) return null;
    return XtreamAccount(
      server: Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null),
      username: user,
      password: password,
    );
  }

  /// Restores a stored account.
  static XtreamAccount? fromJson(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return null;
      final server = Uri.tryParse(json['server'] as String? ?? '');
      final username = json['username'] as String?;
      final password = json['password'] as String?;
      if (server == null || username == null || password == null) return null;
      return XtreamAccount(server: server, username: username, password: password);
    } on Object {
      return null;
    }
  }

  /// `scheme://host[:port]`.
  final Uri server;
  final String username;
  final String password;

  Uri _api(String path, [Map<String, String> extra = const {}]) =>
      server.replace(path: '/$path', queryParameters: {'username': username, 'password': password, ...extra});

  /// The account check (`player_api.php`).
  Uri get authUri => _api('player_api.php');

  /// The whole line-up as M3U with groups and logos.
  Uri get playlistUri => _api('get.php', {'type': 'm3u_plus', 'output': 'ts'});

  /// The provider's XMLTV guide.
  Uri get guideUri => _api('xmltv.php');

  /// A name for the playlist: the server's host.
  String get defaultName => 'Xtream ${server.host}';

  String toJson() => jsonEncode({'server': '$server', 'username': username, 'password': password});
}

/// What `player_api.php` says about the account.
@immutable
final class XtreamStatus {
  const new({required this.authorized, this.status, this.expiresAt, this.maxConnections, this.message});

  final bool authorized;

  /// `Active`, `Expired`, `Banned`, `Disabled` …
  final String? status;
  final DateTime? expiresAt;
  final int? maxConnections;
  final String? message;

  /// Whether the account can play.
  bool get usable => authorized && (status == null || status!.toLowerCase() == 'active');

  /// Why it cannot, in words.
  String get problem => switch (status?.toLowerCase()) {
    _ when !authorized => t.iptv.xtream.wrongCredentials,
    'expired' => t.iptv.xtream.expired,
    'banned' => t.iptv.xtream.banned,
    'disabled' => t.iptv.xtream.disabled,
    _ => t.iptv.xtream.unavailable(status: status ?? t.iptv.xtream.unknownStatus),
  };
}

/// Reads a `player_api.php` answer. Providers write numbers as strings or
/// numbers and dates as Unix seconds.
XtreamStatus parseXtreamStatus(Object? json) {
  if (json is! Map) return const XtreamStatus(authorized: false);
  final info = json['user_info'];
  if (info is! Map) return const XtreamStatus(authorized: false);
  int? number(Object? value) => switch (value) {
    final int n => n,
    final String s => int.tryParse(s.trim()),
    final num n => n.toInt(),
    _ => null,
  };
  final expires = number(info['exp_date']);
  return XtreamStatus(
    authorized: number(info['auth']) == 1,
    status: info['status'] is String ? info['status'] as String : null,
    expiresAt: expires == null || expires <= 0
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true),
    maxConnections: number(info['max_connections']),
    message: info['message'] is String ? info['message'] as String : null,
  );
}

/// Xtream accounts in the encrypted secret store.
final class XtreamVault {
  new(this._secrets);

  final SecretStore _secrets;

  XtreamAccount? read(String id) {
    final raw = _secrets.read(SecretRefs.xtream(id));
    return raw == null ? null : XtreamAccount.fromJson(raw);
  }

  Future<void> save(String id, XtreamAccount account) => _secrets.write(SecretRefs.xtream(id), account.toJson());

  Future<void> delete(String id) => _secrets.write(SecretRefs.xtream(id), null);
}
