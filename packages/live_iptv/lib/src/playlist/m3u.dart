import 'dart:convert';

import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/text.dart';

/// Parses M3U / M3U8 playlists (spec/modules/iptv.md §1.1): `#EXTM3U` header
/// attributes (guide URLs, catch-up and header defaults), `#EXTINF`
/// attributes, `#EXTGRP` groups, `#EXTVLCOPT` / `#EXTHTTP` / `#KODIPROP`
/// request headers and `url|name=value` header options.
///
/// A malformed stanza is skipped with an issue; it never becomes a channel
/// with half its metadata.
abstract final class M3uParser {
  static final _header = RegExp(r'^#EXTM3U(?:\s|$)');
  static const _extInf = '#EXTINF:';
  static const _extGrp = '#EXTGRP:';
  static const _vlcOpt = '#EXTVLCOPT:';
  static const _extHttp = '#EXTHTTP:';
  static const _kodiProp = '#KODIPROP:';

  /// `url|options` entries that are demuxer switches, not headers (Kodi);
  /// a `!` prefix still forces them to be headers.
  static const _transportOptions = {
    'seekable',
    'reconnect_at_eof',
    'reconnect_streamed',
    'reconnect_delay_max',
    'icy',
    'icy_metadata_headers',
    'icy_metadata_packet',
  };

  static const _off = {'0', 'false', 'off', 'none', 'disabled'};

  /// A `%` not followed by two hex digits (Uri.decodeQueryComponent throws an
  /// Error for it).
  static final _badEscape = RegExp('%(?![0-9A-Fa-f]{2})');

  /// Parses [text] (already decoded, see `decodeIptvText`).
  static ParsedPlaylist parse(String text) {
    final lines = text.split(RegExp(r'\r\n?|\n'));
    final entries = <IptvEntry>[];
    final issues = <IptvIssue>[];
    final guideUrls = <Uri>[];
    var header = const <String, String>{};
    var sawContent = false;
    _Metadata? pending;
    var pendingLine = 0;
    var pendingBroken = false;
    var pendingHeaders = <String, String>{};
    var nextHeaders = <String, String>{};
    var nextBroken = false;
    var skipUrl = false;
    String? inheritedGroup;

    for (var i = 0; i < lines.length; i++) {
      final number = i + 1;
      var line = lines[i].trim();
      if (!sawContent && line.startsWith('\uFEFF')) line = line.substring(1).trim();
      if (line.isEmpty) continue;
      if (!sawContent) {
        sawContent = true;
        if (!_header.hasMatch(line)) issues.add(IptvIssue('Missing #EXTM3U header', line: number));
      }
      if (_header.hasMatch(line)) {
        final rest = line.substring('#EXTM3U'.length).trim();
        if (rest.isEmpty) continue;
        try {
          header = {...header, ..._metadata(rest).attributes};
          for (final key in const ['x-tvg-url', 'url-tvg', 'tvg-url']) {
            for (final part in (header[key] ?? '').split(',')) {
              final uri = webUri(part);
              if (uri != null && !guideUrls.contains(uri)) guideUrls.add(uri);
            }
          }
        } on FormatException catch (error) {
          issues.add(IptvIssue(error.message, line: number));
        }
        continue;
      }
      if (line.startsWith(_extInf)) {
        if (pending != null) issues.add(IptvIssue('Missing stream URL', line: pendingLine));
        pending = null;
        pendingLine = number;
        pendingHeaders = nextHeaders;
        pendingBroken = nextBroken;
        nextHeaders = <String, String>{};
        nextBroken = false;
        skipUrl = false;
        try {
          pending = _metadata(line.substring(_extInf.length));
          // An entry's own group-title ends #EXTGRP inheritance, even when empty.
          if (pending.attributes.containsKey('group-title')) inheritedGroup = null;
        } on FormatException catch (error) {
          issues.add(IptvIssue(error.message, line: number));
          skipUrl = true;
        }
        continue;
      }
      if (line.startsWith(_extGrp)) {
        inheritedGroup = nonEmpty(line.substring(_extGrp.length));
        continue;
      }
      if (line.startsWith(_vlcOpt) || line.startsWith(_extHttp) || line.startsWith(_kodiProp)) {
        final target = pending == null ? nextHeaders : pendingHeaders;
        try {
          if (line.startsWith(_vlcOpt)) {
            _httpProperty(target, line.substring(_vlcOpt.length));
          } else if (line.startsWith(_extHttp)) {
            _extHttpHeaders(target, line.substring(_extHttp.length));
          } else {
            _kodiProperty(target, line.substring(_kodiProp.length));
          }
        } on FormatException catch (error) {
          issues.add(IptvIssue(error.message, line: number));
          if (pending == null) {
            nextBroken = true;
          } else {
            pendingBroken = true;
          }
        }
        continue;
      }
      // Other directives and comments are not stream URLs.
      if (line.startsWith('#')) continue;
      if (pending == null) {
        // The URL of a stanza whose #EXTINF was rejected is already reported.
        if (!skipUrl) issues.add(IptvIssue('Stream URL without #EXTINF', line: number));
        skipUrl = false;
        continue;
      }
      if (pendingBroken) {
        issues.add(IptvIssue('Entry skipped: invalid header directive', line: pendingLine));
      } else {
        try {
          entries.add(_entry(pending, line, header, inheritedGroup, pendingHeaders));
        } on FormatException catch (error) {
          issues.add(IptvIssue(error.message, line: number));
        }
      }
      pending = null;
      pendingBroken = false;
      pendingHeaders = <String, String>{};
    }
    if (pending != null) issues.add(IptvIssue('Missing stream URL', line: pendingLine));
    if (!sawContent) issues.add(const IptvIssue('Playlist is empty'));
    return ParsedPlaylist(format: IptvFormat.m3u, entries: entries, guideUrls: guideUrls, issues: issues);
  }

  static IptvEntry _entry(
    _Metadata metadata,
    String rawUrl,
    Map<String, String> header,
    String? inheritedGroup,
    Map<String, String> directiveHeaders,
  ) {
    final (url, urlHeaders) = _streamUrl(rawUrl);
    if (streamUri(url) == null) throw const FormatException('Invalid or unsupported stream URL');
    final attributes = metadata.attributes;
    final name = channelName(metadata.displayName.isNotEmpty ? metadata.displayName : attributes['tvg-name'] ?? '');
    if (name.isEmpty) throw const FormatException('Missing channel name');
    final group = attributes.containsKey('group-title') ? attributes['group-title']! : inheritedGroup ?? '';
    return IptvEntry(
      name: name,
      url: url,
      group: channelName(group),
      tvgId: nonEmpty(attributes['tvg-id']),
      tvgName: nonEmpty(attributes['tvg-name']),
      logo: nonEmpty(attributes['tvg-logo']) ?? nonEmpty(attributes['logo']),
      catchup: _catchup(attributes, header),
      headers: normalizeHeaders({
        ...attributeHeaders(header),
        ...attributeHeaders(attributes),
        ...directiveHeaders,
        ...urlHeaders,
      }),
    );
  }

  /// §4 catch-up attributes; the entry's own values win over the header's.
  /// `timeshift` / `tvg-rec` are old names for a shift window; zero days or
  /// an "off" mode disable catch-up.
  static IptvCatchup _catchup(Map<String, String> attributes, Map<String, String> header) {
    String? pick(String key) => nonEmpty(attributes[key]) ?? nonEmpty(header[key]);
    final source = pick('catchup-source');
    final legacyDays = finiteNumber(attributes['timeshift']) ?? finiteNumber(attributes['tvg-rec']);
    final days = finiteNumber(attributes['catchup-days']) ?? finiteNumber(header['catchup-days']) ?? legacyDays;
    var mode = (pick('catchup') ?? pick('catchup-type'))?.toLowerCase();
    if (_off.contains(mode) || days == 0) {
      mode = 'disabled';
    } else if (mode == null && legacyDays != null && legacyDays > 0) {
      mode = 'shift';
    } else if (mode == null && source != null) {
      mode = 'default';
    }
    final correction = finiteNumber(attributes['catchup-correction']) ?? finiteNumber(header['catchup-correction']);
    return IptvCatchup(mode: mode, source: source, days: days, correction: correction);
  }

  /// `#EXTVLCOPT:http-user-agent=…` and `http-referrer=…`; other VLC options
  /// (`program=1`, …) are ignored.
  static void _httpProperty(Map<String, String> target, String content) {
    final separator = content.indexOf('=');
    final name = headerName(separator < 0 ? content : content.substring(0, separator));
    if (name != 'user-agent' && name != 'referer') return;
    final value = separator < 0 ? '' : content.substring(separator + 1).trim();
    if (value.isEmpty) throw const FormatException('Invalid stream header directive');
    target.addAll(normalizeHeaders({name: value}));
  }

  /// `#KODIPROP:inputstream.adaptive.stream_headers=a=b&c=d` (and
  /// `manifest_headers`); other properties are read like `#EXTVLCOPT`.
  static void _kodiProperty(Map<String, String> target, String content) {
    final separator = content.indexOf('=');
    final name = (separator < 0 ? content : content.substring(0, separator)).trim().toLowerCase();
    if (name.endsWith('.stream_headers') || name.endsWith('.manifest_headers')) {
      final value = separator < 0 ? '' : content.substring(separator + 1);
      if (value.trim().isEmpty) throw const FormatException('Invalid stream header directive');
      target.addAll(_options(value));
      return;
    }
    _httpProperty(target, content);
  }

  /// `#EXTHTTP:{"Cookie":"…"}` (string values only) or `name=value&…`.
  static void _extHttpHeaders(Map<String, String> target, String content) {
    final value = content.trim();
    if (value.isEmpty) throw const FormatException('Invalid EXTHTTP header');
    if (!value.startsWith('{')) {
      target.addAll(_options(value));
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
      if (key is! String || value is! String || normalizeHeaders({key: value}).isEmpty) {
        throw const FormatException('Invalid EXTHTTP header');
      }
    }
    target.addAll(normalizeHeaders(decoded));
  }

  /// Splits `url|name=value&…` into the URL and its headers.
  static (String, Map<String, String>) _streamUrl(String raw) {
    final separator = raw.indexOf('|');
    if (separator < 0) return (raw.trim(), const {});
    final url = raw.substring(0, separator).trim();
    final options = raw.substring(separator + 1);
    if (url.isEmpty || options.trim().isEmpty) throw const FormatException('Invalid stream header option');
    return (url, _options(options, skipTransport: true));
  }

  /// `name=value&…` with percent-decoded names and values.
  static Map<String, String> _options(String options, {bool skipTransport = false}) {
    final headers = <String, String>{};
    for (final option in options.split('&')) {
      final equals = option.indexOf('=');
      if (equals <= 0 || equals == option.length - 1) throw const FormatException('Invalid stream header option');
      if (_badEscape.hasMatch(option)) throw const FormatException('Invalid stream header option');
      final String rawName;
      final String value;
      try {
        rawName = Uri.decodeQueryComponent(option.substring(0, equals).trim());
        value = Uri.decodeQueryComponent(option.substring(equals + 1).trim());
      } on FormatException {
        throw const FormatException('Invalid stream header option');
      }
      if (skipTransport && !rawName.startsWith('!') && _transportOptions.contains(rawName.toLowerCase())) continue;
      final normalized = normalizeHeaders({rawName: value});
      if (normalized.isEmpty) throw const FormatException('Invalid stream header option');
      headers.addAll(normalized);
    }
    return headers;
  }

  /// Reads `key=value` attributes up to the first comma outside quotes; the
  /// rest is the display name, never scanned for attributes. Quoted values
  /// may hold commas and the other quote; unquoted values end at whitespace
  /// or a comma. Bare tokens (the `-1` duration) are skipped. Keys are
  /// lower-cased; a repeated key keeps its last value.
  static _Metadata _metadata(String content) {
    final attributes = <String, String>{};
    var i = 0;
    bool space(int index) {
      final c = content.codeUnitAt(index);
      return c == 32 || (c >= 9 && c <= 13);
    }

    void skipSpace() {
      while (i < content.length && space(i)) {
        i++;
      }
    }

    while (i < content.length) {
      skipSpace();
      if (i == content.length) break;
      if (content[i] == ',') return _Metadata(attributes, content.substring(i + 1).trim());
      final keyStart = i;
      while (i < content.length && !space(i) && content[i] != '=' && content[i] != ',') {
        i++;
      }
      final key = content.substring(keyStart, i).toLowerCase();
      skipSpace();
      if (i == content.length || content[i] != '=') continue;
      if (key.isEmpty) throw const FormatException('Missing attribute key');
      i++;
      skipSpace();
      String value;
      if (i < content.length && (content[i] == '"' || content[i] == "'")) {
        final quote = content[i++];
        final start = i;
        while (i < content.length && content[i] != quote) {
          i++;
        }
        if (i == content.length) throw const FormatException('Unclosed attribute quote');
        value = content.substring(start, i++);
        if (i < content.length && !space(i) && content[i] != ',') {
          throw const FormatException('Missing separator after quoted attribute');
        }
      } else {
        final start = i;
        while (i < content.length && !space(i) && content[i] != ',') {
          i++;
        }
        value = content.substring(start, i);
      }
      attributes[key] = value.trim();
    }
    return _Metadata(attributes, '');
  }
}

final class _Metadata {
  const new(this.attributes, this.displayName);

  final Map<String, String> attributes;
  final String displayName;
}
