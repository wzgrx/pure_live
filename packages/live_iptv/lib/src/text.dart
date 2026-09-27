import 'dart:convert';
import 'dart:io' show gzip;

/// Decodes a downloaded or picked playlist or guide file (spec/modules/iptv.md
/// §1): gzip is unpacked (`.xml.gz` guides), a UTF-8 or UTF-16 byte order mark
/// picks the encoding and is removed, anything else is UTF-8 with malformed
/// bytes replaced. Legacy GBK files are not converted (known gap).
String decodeIptvText(List<int> bytes) {
  var data = bytes;
  if (data.length >= 2 && data[0] == 0x1f && data[1] == 0x8b) {
    try {
      data = gzip.decode(data);
    } on FormatException {
      // Not really gzip: read the bytes as they are.
    }
  }
  if (data.length >= 3 && data[0] == 0xef && data[1] == 0xbb && data[2] == 0xbf) {
    return utf8.decode(data.sublist(3), allowMalformed: true);
  }
  if (data.length >= 2 && data[0] == 0xff && data[1] == 0xfe) return _utf16(data.sublist(2), littleEndian: true);
  if (data.length >= 2 && data[0] == 0xfe && data[1] == 0xff) return _utf16(data.sublist(2), littleEndian: false);
  final text = utf8.decode(data, allowMalformed: true);
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

String _utf16(List<int> bytes, {required bool littleEndian}) {
  final units = List<int>.generate(
    bytes.length ~/ 2,
    (i) => littleEndian ? bytes[2 * i] | (bytes[2 * i + 1] << 8) : (bytes[2 * i] << 8) | bytes[2 * i + 1],
  );
  return String.fromCharCodes(units);
}

/// URL schemes a playlist entry may use: what the player (mpv with FFmpeg)
/// opens. Proprietary schemes such as `p2p://` or TVBox `proxy://` are
/// rejected with an issue.
const streamSchemes = {'http', 'https', 'rtmp', 'rtmps', 'rtsp', 'rtsps', 'rtp', 'udp', 'mms', 'mmsh', 'srt'};

/// The stream URL in [text], or null when it is not an absolute URL with a
/// [streamSchemes] scheme and a host.
Uri? streamUri(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !streamSchemes.contains(uri.scheme.toLowerCase())) return null;
  return uri.host.isEmpty ? null : uri;
}

/// An http(s) URL, or null.
Uri? webUri(String? text) {
  final uri = Uri.tryParse(text?.trim() ?? '');
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) return null;
  return uri;
}

/// A trimmed non-empty string, or null.
String? nonEmpty(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// A channel name as the identity of a channel: trimmed, runs of whitespace
/// collapsed to one space.
String channelName(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Header names playlists spell differently, mapped to the HTTP name.
const _headerAliases = {
  'http-user-agent': 'user-agent',
  'http-referrer': 'referer',
  'http-referer': 'referer',
  'referrer': 'referer',
  'cookies': 'cookie',
};

final _headerName = RegExp(r'^[a-z0-9-]+$');
final _control = RegExp(r'[\u0000-\u001F\u007F]+');

/// The HTTP header name for a playlist's [raw] name: lower case, a leading
/// `!` (forced header in Kodi options) removed, aliases such as
/// `http-user-agent` mapped; null when it is not a valid token.
String? headerName(String raw) {
  var name = raw.trim().toLowerCase();
  if (name.startsWith('!')) name = name.substring(1);
  name = _headerAliases[name] ?? name;
  return name.isNotEmpty && _headerName.hasMatch(name) ? name : null;
}

/// Headers with canonical names ([headerName]) and control characters
/// replaced by spaces; entries with an invalid name or an empty value are
/// dropped. Keys are sorted, so the same headers always encode the same way.
Map<String, String> normalizeHeaders(Map<Object?, Object?> source) {
  final result = <String, String>{};
  for (final MapEntry(:key, :value) in source.entries) {
    if (key is! String || value is! String) continue;
    final name = headerName(key);
    final text = value.replaceAll(_control, ' ').trim();
    if (name != null && text.isNotEmpty) result[name] = text;
  }
  final names = result.keys.toList()..sort();
  return {for (final name in names) name: result[name]!};
}

/// Headers from playlist attributes that name request headers
/// (`http-user-agent="…"`, `referrer="…"`, …).
Map<String, String> attributeHeaders(Map<String, String> attributes) => normalizeHeaders({
  for (final name in const [
    'user-agent',
    'http-user-agent',
    'referer',
    'referrer',
    'http-referer',
    'http-referrer',
    'origin',
    'authorization',
    'cookie',
    'cookies',
  ])
    if (attributes[name] case final value? when value.trim().isNotEmpty) name: value,
});

/// A finite number from [text], or null.
double? finiteNumber(String? text) {
  final value = double.tryParse(text?.trim() ?? '');
  return value != null && value.isFinite ? value : null;
}
