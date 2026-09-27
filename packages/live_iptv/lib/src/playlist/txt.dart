import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/text.dart';

/// Parses TXT playlists (spec/modules/iptv.md §1.2): `group,#genre#` starts a
/// group; `name,url` is a channel, where `url` may list several sources
/// separated by `#`, each optionally labelled `url$label`. Every source is a
/// line of the same channel.
abstract final class TxtParser {
  static final _genre = RegExp(r',\s*#genre#\s*$', caseSensitive: false);

  /// Parses [text] (already decoded).
  static ParsedPlaylist parse(String text) {
    final entries = <IptvEntry>[];
    final issues = <IptvIssue>[];
    var group = '';
    final lines = text.split(RegExp(r'\r\n?|\n'));
    for (var i = 0; i < lines.length; i++) {
      final number = i + 1;
      var line = lines[i].trim();
      if (i == 0 && line.startsWith('\uFEFF')) line = line.substring(1).trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
      if (_genre.hasMatch(line)) {
        group = channelName(line.substring(0, line.indexOf(',')));
        continue;
      }
      final comma = line.indexOf(',');
      if (comma <= 0) {
        issues.add(IptvIssue('Not a "name,url" line', line: number));
        continue;
      }
      final name = channelName(line.substring(0, comma));
      if (name.isEmpty) {
        issues.add(IptvIssue('Missing channel name', line: number));
        continue;
      }
      final sources = line.substring(comma + 1).split('#');
      var added = false;
      for (final source in sources) {
        final url = _withoutLabel(source.trim());
        if (url.isEmpty) continue;
        if (streamUri(url) == null) {
          issues.add(IptvIssue('Invalid or unsupported stream URL', line: number));
          continue;
        }
        entries.add(IptvEntry(name: name, url: url, group: group));
        added = true;
      }
      if (!added && sources.every((source) => source.trim().isEmpty)) {
        issues.add(IptvIssue('Missing stream URL', line: number));
      }
    }
    if (entries.isEmpty && issues.isEmpty) issues.add(const IptvIssue('Playlist is empty'));
    return ParsedPlaylist(format: IptvFormat.txt, entries: entries, issues: issues);
  }

  /// `http://host/live.m3u8$电信` → the URL: in these lists a `$` always
  /// starts a line label (a URL that is invalid without its `$…` part is
  /// kept whole).
  static String _withoutLabel(String source) {
    final dollar = source.lastIndexOf(r'$');
    if (dollar <= 0) return source;
    final url = source.substring(0, dollar).trim();
    return streamUri(url) != null ? url : source;
  }
}
