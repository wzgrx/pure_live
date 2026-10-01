import 'dart:convert';

import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/playlist/playlist_parse_result.dart';
import 'package:live_net/live_net.dart';

/// Parses M3U and M3U Plus playlists (3.x `M3uParser`).
///
/// - `#EXTINF` attributes are read one at a time up to the first comma
///   outside quotes; the rest of the line is the display name, never scanned
///   for attributes. Quoted values may hold commas and the other quote;
///   unquoted values end at whitespace or a comma; keys are case-insensitive
///   and the last duplicate wins.
/// - `#EXTGRP:` starts an inherited group, an empty one clears it, and an
///   entry with its own `group-title` (even empty) ends the inheritance.
/// - Request headers, later ones winning: `#EXTM3U` header attributes,
///   `#EXTINF` attributes, the `#EXTVLCOPT`, `#EXTHTTP` and `#KODIPROP`
///   directives (before `#EXTINF` they apply to the next entry, after it to
///   the current one), then the `url|name=value&...` suffix.
/// - Catch-up attributes of the entry win over the header's; `timeshift` /
///   `tvg-rec` days mean `shift`, a `catchup-source` alone means `default`,
///   and `0`/`false`/`off`/`none`/`disabled` or zero days disable it.
///
/// A broken stanza (bad quoting, malformed header directive, unsupported
/// URL, no name) is reported and skipped; the rest of the list is kept.
final class M3uParser {
  /// Creates a parser.
  const new();

  static const String _extInf = '#EXTINF:';
  static const String _extGrp = '#EXTGRP:';
  static const String _extVlcOpt = '#EXTVLCOPT:';
  static const String _extHttp = '#EXTHTTP:';
  static const String _kodiProp = '#KODIPROP:';

  /// URL schemes 3.x accepted in M3U playlists.
  static const Set<String> schemes = {'http', 'https', 'rtmp', 'rtsp', 'udp', 'mms'};

  static const Set<String> _transportOptions = {
    'seekable',
    'reconnect_at_eof',
    'reconnect_streamed',
    'reconnect_delay_max',
    'icy',
    'icy_metadata_headers',
    'icy_metadata_packet',
  };

  static final RegExp _header = RegExp(r'^#EXTM3U(?:\s|$)');
  static final RegExp _badPercent = RegExp('%(?![0-9a-fA-F]{2})');

  /// Parses [content].
  PlaylistParseResult parse(String content) {
    final lines = content.split(RegExp(r'\r\n?|\n'));
    final entries = <IptvEntry>[];
    final issues = <PlaylistIssue>[];
    var sawContent = false;
    var truncated = false;
    _Metadata? pending;
    var pendingLine = 0;
    var pendingBroken = false;
    String? directiveGroup;
    var headerAttributes = const <String, String>{};
    var pendingHeaders = <String, String>{};
    var nextEntryHeaders = <String, String>{};
    var nextEntryBroken = false;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      final number = i + 1;
      if (line.isEmpty) continue;
      if (!sawContent) {
        sawContent = true;
        if (!_header.hasMatch(line)) issues.add(PlaylistIssue(number, 'Missing #EXTM3U header'));
      }
      if (_header.hasMatch(line)) {
        final headerMetadata = line.substring('#EXTM3U'.length).trim();
        if (headerMetadata.isNotEmpty) {
          try {
            headerAttributes = _parseMetadata(headerMetadata).attributes;
          } on FormatException catch (e) {
            issues.add(PlaylistIssue(number, e.message));
          }
        }
        continue;
      }
      if (line.startsWith(_extInf)) {
        if (pending != null || pendingBroken) issues.add(PlaylistIssue(pendingLine, 'Missing stream URL'));
        pending = null;
        pendingBroken = false;
        pendingHeaders = nextEntryHeaders;
        nextEntryHeaders = <String, String>{};
        pendingLine = number;
        try {
          final metadata = _parseMetadata(line.substring(_extInf.length));
          // A group-title belongs to this entry and ends EXTGRP inheritance.
          if (metadata.attributes.containsKey('group-title')) directiveGroup = null;
          if (!nextEntryBroken) pending = metadata;
        } on FormatException catch (e) {
          issues.add(PlaylistIssue(number, e.message));
        }
        pendingBroken = pending == null;
        nextEntryBroken = false;
        continue;
      }
      if (line.startsWith(_extGrp)) {
        directiveGroup = _emptyToNull(line.substring(_extGrp.length).trim());
        continue;
      }
      if (line.startsWith(_extVlcOpt) || line.startsWith(_extHttp) || line.startsWith(_kodiProp)) {
        final current = pending != null || pendingBroken;
        final target = current ? pendingHeaders : nextEntryHeaders;
        try {
          if (line.startsWith(_extVlcOpt)) {
            _applyHttpProperty(target, line.substring(_extVlcOpt.length));
          } else if (line.startsWith(_extHttp)) {
            _applyExtHttp(target, line.substring(_extHttp.length));
          } else {
            _applyKodiProperty(target, line.substring(_kodiProp.length));
          }
        } on FormatException catch (e) {
          issues.add(PlaylistIssue(number, e.message));
          // Never send a stream without the authentication it asked for.
          if (current) {
            pending = null;
            pendingBroken = true;
          } else {
            nextEntryBroken = true;
          }
        }
        continue;
      }
      // Unknown extension directives are not stream URLs.
      if (line.startsWith('#')) continue;
      if (pending != null) {
        try {
          entries.add(_entry(pending, line, directiveGroup, headerAttributes, pendingHeaders));
        } on FormatException catch (e) {
          issues.add(PlaylistIssue(number, e.message));
        }
      }
      pending = null;
      pendingBroken = false;
      pendingHeaders = <String, String>{};
    }
    if (pending != null || pendingBroken) {
      issues.add(PlaylistIssue(pendingLine, 'Missing stream URL'));
      truncated = true;
    }
    if (!sawContent) issues.add(const PlaylistIssue(0, 'Playlist content is empty'));
    return PlaylistParseResult(entries: entries, issues: issues, truncated: truncated);
  }

  IptvEntry _entry(
    _Metadata metadata,
    String url,
    String? directiveGroup,
    Map<String, String> headerAttributes,
    Map<String, String> directiveHeaders,
  ) {
    final stream = _parseStreamUrl(url);
    if (!isSupportedStreamUrl(stream.url, schemes)) throw const FormatException('Invalid or unsupported stream URL');
    final attrs = {...metadata.attributes};
    if (!attrs.containsKey('group-title') && directiveGroup != null) attrs['group-title'] = directiveGroup;
    final name = metadata.displayName.isNotEmpty ? metadata.displayName : attrs['tvg-name'];
    if (name == null || name.isEmpty) throw const FormatException('Missing channel name');

    final catchupSource = _emptyToNull(attrs['catchup-source']) ?? _emptyToNull(headerAttributes['catchup-source']);
    final legacyDays = _finiteDouble(attrs['timeshift']) ?? _finiteDouble(attrs['tvg-rec']);
    final catchupDays =
        _finiteDouble(attrs['catchup-days']) ?? _finiteDouble(headerAttributes['catchup-days']) ?? legacyDays;
    var catchupMode =
        (_emptyToNull(attrs['catchup']) ??
                _emptyToNull(attrs['catchup-type']) ??
                _emptyToNull(headerAttributes['catchup']) ??
                _emptyToNull(headerAttributes['catchup-type']))
            ?.toLowerCase();
    if (disabledCatchupModes.contains(catchupMode) || catchupDays == 0) {
      catchupMode = 'disabled';
    } else if (catchupMode == null && legacyDays != null && legacyDays > 0) {
      catchupMode = 'shift';
    } else if (catchupMode == null && catchupSource != null) {
      catchupMode = 'default';
    }
    return IptvEntry(
      name: name,
      streamUrl: stream.url,
      tvgId: _emptyToNull(attrs['tvg-id']),
      tvgName: _emptyToNull(attrs['tvg-name']),
      tvgLogo: _emptyToNull(attrs['tvg-logo']),
      groupTitle: _emptyToNull(attrs['group-title']),
      channelNumber: int.tryParse(attrs['tvg-chno'] ?? ''),
      streamType: _streamType(attrs['group-title'], stream.url),
      catchupMode: catchupMode,
      catchupSource: catchupSource,
      catchupDays: catchupDays,
      catchupCorrectionHours:
          _finiteDouble(attrs['catchup-correction']) ?? _finiteDouble(headerAttributes['catchup-correction']),
      httpHeaders: HttpHeaderPolicy.normalize({
        ..._metadataHeaders(headerAttributes),
        ..._metadataHeaders(attrs),
        ...directiveHeaders,
        ...stream.headers,
      }),
    );
  }

  static Map<String, String> _metadataHeaders(Map<String, String> attributes) => {
    for (final key in const [
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
      if (attributes[key] case final value? when value.trim().isNotEmpty) key: value,
  };

  static void _applyHttpProperty(Map<String, String> target, String content) {
    final separator = content.indexOf('=');
    final rawName = separator < 0 ? content.trim() : content.substring(0, separator).trim();
    final canonical = HttpHeaderPolicy.canonicalName(rawName);
    if (canonical != 'user-agent' && canonical != 'referer') return;
    if (separator <= 0 || separator == content.length - 1) {
      throw const FormatException('Invalid stream header directive');
    }
    final normalized = HttpHeaderPolicy.normalize({canonical: content.substring(separator + 1).trim()});
    if (normalized.isEmpty) throw const FormatException('Invalid stream header directive');
    target.addAll(normalized);
  }

  static void _applyKodiProperty(Map<String, String> target, String content) {
    final separator = content.indexOf('=');
    final name = (separator < 0 ? content : content.substring(0, separator)).trim().toLowerCase();
    if (name.endsWith('.stream_headers') || name.endsWith('.manifest_headers')) {
      if (separator <= 0 || separator == content.length - 1) {
        throw const FormatException('Invalid stream header directive');
      }
      target.addAll(_parseHeaderOptions(content.substring(separator + 1)));
      return;
    }
    _applyHttpProperty(target, content);
  }

  static void _applyExtHttp(Map<String, String> target, String content) {
    final value = content.trim();
    if (value.isEmpty) throw const FormatException('Invalid EXTHTTP header');
    if (!value.startsWith('{')) {
      target.addAll(_parseHeaderOptions(value));
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      throw const FormatException('Invalid EXTHTTP header');
    }
    if (decoded is! Map) throw const FormatException('Invalid EXTHTTP header');
    for (final MapEntry(:key, :value) in decoded.entries) {
      if (key is! String || value is! String || HttpHeaderPolicy.normalize({key: value}).isEmpty) {
        throw const FormatException('Invalid EXTHTTP header');
      }
    }
    target.addAll(HttpHeaderPolicy.normalize(decoded));
  }

  static ({String url, Map<String, String> headers}) _parseStreamUrl(String raw) {
    final separator = raw.indexOf('|');
    if (separator < 0) return (url: raw.trim(), headers: const {});
    final url = raw.substring(0, separator).trim();
    final options = raw.substring(separator + 1);
    if (url.isEmpty || options.trim().isEmpty) throw const FormatException('Invalid stream header option');
    return (url: url, headers: _parseHeaderOptions(options, ignoreTransportOptions: true));
  }

  static Map<String, String> _parseHeaderOptions(String options, {bool ignoreTransportOptions = false}) {
    final headers = <String, String>{};
    for (final option in options.split('&')) {
      final equals = option.indexOf('=');
      if (equals <= 0 || equals == option.length - 1 || _badPercent.hasMatch(option)) {
        throw const FormatException('Invalid stream header option');
      }
      try {
        final rawName = Uri.decodeQueryComponent(option.substring(0, equals).trim());
        final value = Uri.decodeQueryComponent(option.substring(equals + 1).trim());
        if (ignoreTransportOptions && !rawName.startsWith('!') && _transportOptions.contains(rawName.toLowerCase())) {
          continue;
        }
        final normalized = HttpHeaderPolicy.normalize({rawName: value});
        if (normalized.isEmpty) throw const FormatException('Invalid stream header option');
        headers.addAll(normalized);
      } on FormatException {
        throw const FormatException('Invalid stream header option');
      }
    }
    return HttpHeaderPolicy.normalize(headers);
  }

  /// Reads one attribute at a time, stopping at the first comma outside a
  /// quoted value.
  static _Metadata _parseMetadata(String content) {
    final attributes = <String, String>{};
    var i = 0;
    while (i < content.length) {
      while (i < content.length && _space(content.codeUnitAt(i))) {
        i++;
      }
      if (i == content.length) break;
      if (content[i] == ',') return _Metadata(attributes, content.substring(i + 1).trim());
      final keyStart = i;
      while (i < content.length && !_space(content.codeUnitAt(i)) && content[i] != '=' && content[i] != ',') {
        i++;
      }
      final key = content.substring(keyStart, i).toLowerCase();
      while (i < content.length && _space(content.codeUnitAt(i))) {
        i++;
      }
      // Skip the duration and unknown bare tokens without losing the next key.
      if (i == content.length || content[i] != '=') continue;
      if (key.isEmpty) throw const FormatException('Missing attribute key');
      i++;
      while (i < content.length && _space(content.codeUnitAt(i))) {
        i++;
      }
      String value;
      if (i < content.length && (content[i] == '"' || content[i] == "'")) {
        final quote = content[i++];
        final start = i;
        while (i < content.length && content[i] != quote) {
          i++;
        }
        if (i == content.length) throw const FormatException('Unclosed attribute quote');
        value = content.substring(start, i++);
        if (i < content.length && !_space(content.codeUnitAt(i)) && content[i] != ',') {
          throw const FormatException('Missing separator after quoted attribute');
        }
      } else {
        final start = i;
        while (i < content.length && !_space(content.codeUnitAt(i)) && content[i] != ',') {
          i++;
        }
        value = content.substring(start, i);
      }
      attributes[key] = value.trim();
    }
    // Without a display delimiter the tvg-name fallback still applies.
    return _Metadata(attributes, '');
  }

  static bool _space(int c) => c == 32 || (c >= 9 && c <= 13);

  static IptvStreamType _streamType(String? group, String url) {
    final lowerGroup = group?.toLowerCase() ?? '';
    final lowerUrl = url.toLowerCase();
    if (lowerGroup.contains('vod') || lowerGroup.contains('movie') || lowerUrl.contains('/movie/')) {
      return IptvStreamType.vod;
    }
    if (lowerGroup.contains('series') || lowerUrl.contains('/series/')) return IptvStreamType.series;
    return IptvStreamType.live;
  }

  static String? _emptyToNull(String? value) => value == null || value.isEmpty ? null : value;

  static double? _finiteDouble(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }
}

/// Catch-up modes that mean "off".
const Set<String> disabledCatchupModes = {'0', 'false', 'off', 'none', 'disabled'};

/// Whether [url] parses with one of [schemes].
bool isSupportedStreamUrl(String url, Set<String> schemes) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.hasScheme && schemes.contains(uri.scheme.toLowerCase());
}

final class _Metadata {
  const new(this.attributes, this.displayName);

  final Map<String, String> attributes;
  final String displayName;
}
