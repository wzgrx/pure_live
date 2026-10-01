import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/playlist/m3u_parser.dart';
import 'package:live_iptv/src/playlist/playlist_parse_result.dart';
import 'package:live_iptv/src/playlist/txt_parser.dart';

/// Parses [content] as [format].
PlaylistParseResult parsePlaylist(String content, IptvPlaylistFormat format) => switch (format) {
  IptvPlaylistFormat.m3u => const M3uParser().parse(content),
  IptvPlaylistFormat.txt => const TxtParser().parse(content),
};

/// The format of downloaded or pasted [content] (3.x's rules for URL and web
/// imports): `#EXTM3U` first is M3U; a `,#genre#` line or a `.txt` [path] is
/// TXT; otherwise a `.m3u`/`.m3u8` [path] is M3U, and anything else is not a
/// playlist (null).
IptvPlaylistFormat? detectPlaylistFormat(String content, {String path = ''}) {
  final text = content.trim();
  final byPath = IptvPlaylistFormat.fromPath(path);
  if (text.startsWith('#EXTM3U')) return IptvPlaylistFormat.m3u;
  if (text.contains(',#genre#') || byPath == IptvPlaylistFormat.txt) return IptvPlaylistFormat.txt;
  return byPath;
}
