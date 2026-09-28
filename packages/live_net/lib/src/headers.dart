import 'dart:convert';

/// Canonical form of externally supplied HTTP headers (IPTV playlists, user
/// input) before they reach the player, the recorder or storage.
///
/// Names are case-insensitive; the stored form is lower case and sorted, so
/// reloading a playlist does not look like a change just because map order
/// differs.
abstract final class HttpHeaderPolicy {
  static final RegExp _validName = RegExp(r'^[a-z0-9-]+$');
  static final RegExp _controls = RegExp(r'[\u0000-\u001F\u007F]+');

  /// String entries of [source] with canonical names and single-line values;
  /// invalid names and empty values are dropped.
  static Map<String, String> normalize(Map<Object?, Object?>? source) {
    if (source == null || source.isEmpty) return const <String, String>{};
    final result = <String, String>{};
    for (final MapEntry(:key, :value) in source.entries) {
      if (key is! String || value is! String) continue;
      final name = canonicalName(key);
      final cleaned = value.replaceAll(_controls, ' ').trim();
      if (name != null && cleaned.isNotEmpty) result[name] = cleaned;
    }
    if (result.isEmpty) return const <String, String>{};
    final entries = result.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, String>.unmodifiable(Map<String, String>.fromEntries(entries));
  }

  /// The lower-case header name for [raw], resolving the aliases playlists
  /// use (`http-user-agent`, `http-referrer`, `referrer`, `cookies`, a
  /// leading `!`); null when it is not a valid header name.
  static String? canonicalName(String raw) {
    var name = raw.trim().toLowerCase();
    if (name.startsWith('!')) name = name.substring(1);
    name = switch (name) {
      'http-user-agent' => 'user-agent',
      'http-referrer' || 'http-referer' || 'referrer' => 'referer',
      'cookies' => 'cookie',
      _ => name,
    };
    return name.isNotEmpty && _validName.hasMatch(name) ? name : null;
  }

  /// [source] normalized as a JSON object, or null when nothing is left.
  static String? encode(Map<Object?, Object?>? source) {
    final normalized = normalize(source);
    return normalized.isEmpty ? null : jsonEncode(normalized);
  }

  /// Headers from [encode]'s output; anything unreadable gives none.
  static Map<String, String> decode(String? encoded) {
    final value = encoded?.trim();
    if (value == null || value.isEmpty) return const <String, String>{};
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? normalize(decoded) : const <String, String>{};
    } on FormatException {
      return const <String, String>{};
    }
  }
}
