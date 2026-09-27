/// IPTV for Pure Live v4 (spec/modules/iptv.md, ADR 0003): playlist and
/// programme guide parsers, guide matching, catch-up URLs and the "网络电视"
/// source that plays channels through the normal room path. Pure Dart;
/// storage is behind `IptvRepository`.
library;

export 'src/catchup.dart';
export 'src/fetch.dart';
export 'src/guide/guide_parser.dart';
export 'src/guide/json_guide.dart' show JsonGuideParser, parseGuideTime;
export 'src/guide/matcher.dart';
export 'src/guide/xmltv.dart';
export 'src/iptv_site.dart';
export 'src/model.dart';
export 'src/playlist/json.dart';
export 'src/playlist/m3u.dart';
export 'src/playlist/playlist_parser.dart';
export 'src/playlist/txt.dart';
export 'src/repository.dart';
export 'src/text.dart' show channelName, decodeIptvText, normalizeHeaders, streamSchemes, streamUri;
