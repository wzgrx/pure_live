import 'dart:convert';

import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/text.dart';

/// Parses JSON playlists (spec/modules/iptv.md §1.3). Accepted shapes:
///
/// - an array of channels;
/// - `{"channels": [...]}`, optionally with `"epg"` / `"x-tvg-url"`;
/// - `{"groups": [{"name": …, "channels": [...]}]}`;
/// - TVBox `{"lives": [{"group": …, "channels": [{"name": …, "urls": [...]}]}]}`.
///
/// A channel has a name (`name`, `title`, `channel`, `channel_name`) and one
/// or more URLs (`url`, `urls`, `src`, `stream`, `link`; a string may list
/// several separated by `#`), optionally `group`, `logo`, `tvg-id`,
/// `tvg-name`, `catchup*` and `headers` / `ua` / `referer`.
abstract final class JsonPlaylistParser {
  /// Parses [text]; throws [FormatException] when it is not JSON.
  static ParsedPlaylist parse(String text) {
    final decoded = jsonDecode(text);
    final entries = <IptvEntry>[];
    final issues = <IptvIssue>[];
    final guideUrls = <Uri>[];

    void channels(Object? list, String group) {
      if (list is! List) return;
      for (final item in list) {
        if (item is Map<String, Object?>) {
          _channel(item, group, entries, issues);
        } else {
          issues.add(const IptvIssue('Channel is not an object'));
        }
      }
    }

    void groups(Object? list) {
      if (list is! List) return;
      for (final item in list) {
        if (item is! Map<String, Object?>) continue;
        final group = channelName(_text(item, const ['group', 'name', 'title', 'category']) ?? '');
        if (item['channels'] is List) {
          channels(item['channels'], group);
        } else if (_text(item, const ['url', 'api']) != null) {
          // TVBox live source pointing to another playlist: not followed.
          issues.add(IptvIssue('Linked playlist not followed: ${_text(item, const ['url', 'api'])}'));
        }
      }
    }

    switch (decoded) {
      case final List<Object?> list:
        channels(list, '');
      case final Map<String, Object?> map:
        for (final key in const ['epg', 'x-tvg-url', 'url-tvg', 'tvgUrl', 'epgUrl']) {
          final uri = webUri(map[key] is String ? map[key]! as String : null);
          if (uri != null && !guideUrls.contains(uri)) guideUrls.add(uri);
        }
        channels(map['channels'], '');
        groups(map['groups']);
        groups(map['lives']);
      default:
        throw const FormatException('JSON playlist must be an array or an object');
    }
    if (entries.isEmpty && issues.isEmpty) issues.add(const IptvIssue('No channels in the JSON playlist'));
    return ParsedPlaylist(format: IptvFormat.json, entries: entries, guideUrls: guideUrls, issues: issues);
  }

  static void _channel(Map<String, Object?> item, String group, List<IptvEntry> entries, List<IptvIssue> issues) {
    final name = channelName(_text(item, const ['name', 'title', 'channel', 'channel_name', 'channelName']) ?? '');
    if (name.isEmpty) {
      issues.add(const IptvIssue('Missing channel name'));
      return;
    }
    final urls = <String>[
      for (final key in const ['urls', 'url', 'src', 'stream', 'link'])
        ...switch (item[key]) {
          final String text => text.split('#'),
          final List<Object?> list => [for (final value in list) ?nonEmpty(value)],
          _ => const <String>[],
        },
    ].map((url) => url.trim()).where((url) => url.isNotEmpty).toList();
    if (urls.isEmpty) {
      issues.add(IptvIssue('Missing stream URL: $name'));
      return;
    }
    final headers = <String, String>{
      if (item['headers'] case final Map<Object?, Object?> map) ...normalizeHeaders(map),
      'user-agent': ?_text(item, const ['ua', 'userAgent', 'user-agent']),
      'referer': ?_text(item, const ['referer', 'referrer']),
    };
    final days = switch (item['catchup-days'] ?? item['catchupDays']) {
      final num number when number.isFinite => number.toDouble(),
      final String text => finiteNumber(text),
      _ => null,
    };
    var mode = _text(item, const ['catchup', 'catchup-type', 'catchupType'])?.toLowerCase();
    final source = _text(item, const ['catchup-source', 'catchupSource']);
    if (const {'0', 'false', 'off', 'none', 'disabled'}.contains(mode) || days == 0) {
      mode = 'disabled';
    } else if (mode == null && source != null) {
      mode = 'default';
    }
    final itemGroup = _text(item, const ['group', 'group-title', 'groupTitle', 'category', 'genre']);
    for (final url in urls) {
      if (streamUri(url) == null) {
        issues.add(IptvIssue('Invalid or unsupported stream URL: $name'));
        continue;
      }
      entries.add(
        IptvEntry(
          name: name,
          url: url,
          group: channelName(itemGroup ?? group),
          tvgId: _text(item, const ['tvg-id', 'tvgId', 'epgId', 'epg-id', 'epg_id']),
          tvgName: _text(item, const ['tvg-name', 'tvgName', 'epgName']),
          logo: _text(item, const ['logo', 'tvg-logo', 'tvgLogo', 'icon', 'image']),
          catchup: IptvCatchup(mode: mode, source: source, days: days),
          headers: normalizeHeaders(headers),
        ),
      );
    }
  }

  static String? _text(Map<String, Object?> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is String || value is num) {
        final text = nonEmpty(value);
        if (text != null) return text;
      }
    }
    return null;
  }
}
