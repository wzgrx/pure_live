import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/playlist/m3u_parser.dart';
import 'package:live_iptv/src/playlist/playlist_parse_result.dart';

/// Parses `name,url` playlists with `group,#genre#` lines (3.x `TxtParser`).
///
/// - Channels before the first genre line are in `Uncategorized`; genre
///   lines whose name contains `更新时间` or `提示` (notes, not groups) keep
///   the current group.
/// - A URL part may hold several sources split by `#`; each becomes an entry
///   named `name (线路N)`, numbered over the valid sources.
/// - Lines without a comma, with an empty side, or whose name starts with
///   `—` or `[` are skipped silently; invalid sources are dropped.
final class TxtParser {
  /// Creates a parser.
  const new();

  /// The group of channels before any genre line.
  static const String defaultGroup = 'Uncategorized';

  /// URL schemes 3.x accepted in TXT playlists.
  static const Set<String> schemes = {'http', 'https', 'rtmp', 'rtsp', 'udp', 'mms', 'p2p'};

  static final RegExp _genre = RegExp(r',\s*#genre#\s*$', caseSensitive: false);

  /// Parses [content].
  PlaylistParseResult parse(String content) {
    final entries = <IptvEntry>[];
    var group = defaultGroup;
    for (final raw in content.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (_genre.hasMatch(line)) {
        final name = line.split(',').first.trim();
        if (name.isNotEmpty && !name.contains('更新时间') && !name.contains('提示')) group = name;
        continue;
      }
      final comma = line.indexOf(',');
      if (comma == -1 || comma == line.length - 1) continue;
      final name = line.substring(0, comma).trim();
      final urls = line.substring(comma + 1).trim();
      if (name.isEmpty || urls.isEmpty || name.startsWith('—') || name.startsWith('[')) continue;
      final sources = urls.split('#');
      var index = 1;
      for (final source in sources) {
        final url = source.trim();
        if (url.isEmpty || !isSupportedStreamUrl(url, schemes)) continue;
        entries.add(IptvEntry(name: sources.length > 1 ? '$name (线路$index)' : name, streamUrl: url, groupTitle: group));
        index++;
      }
    }
    return PlaylistParseResult(entries: entries);
  }
}
