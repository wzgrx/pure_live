import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/playlist/json.dart';
import 'package:live_iptv/src/playlist/m3u.dart';
import 'package:live_iptv/src/playlist/txt.dart';
import 'package:live_iptv/src/text.dart';

/// Parses a playlist of any supported format, detected from the content
/// (spec/modules/iptv.md §1): `#EXTM3U` or `#EXTINF` → M3U; a leading `{` or
/// `[` → JSON; anything else → TXT. File names and content types are not
/// trusted: servers send M3U as `text/plain` and TXT lists as `.m3u`.
ParsedPlaylist parsePlaylist(String text) {
  final body = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final head = body.trimLeft();
  if (head.startsWith('#EXTM3U') || head.contains('#EXTINF:')) return M3uParser.parse(body);
  if (head.startsWith('{') || head.startsWith('[')) {
    try {
      return JsonPlaylistParser.parse(body);
    } on FormatException catch (error) {
      return ParsedPlaylist(format: IptvFormat.json, entries: const [], issues: [IptvIssue(error.message)]);
    }
  }
  return TxtParser.parse(body);
}

/// Parses a playlist file's bytes ([decodeIptvText], then [parsePlaylist]).
ParsedPlaylist parsePlaylistBytes(List<int> bytes) => parsePlaylist(decodeIptvText(bytes));
