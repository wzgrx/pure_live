import 'package:meta/meta.dart';

/// One `#EXT-X-STREAM-INF` entry of an HLS master playlist.
@immutable
final class HlsVariant {
  /// Creates a variant.
  const new({
    required this.url,
    required this.bandwidth,
    this.width,
    this.height,
    this.frameRate,
    this.codecs,
    this.name,
  });

  /// Media playlist URL, resolved against the master's URL.
  final Uri url;

  /// `BANDWIDTH`, bits per second.
  final int bandwidth;

  /// Width from `RESOLUTION`.
  final int? width;

  /// Height from `RESOLUTION`.
  final int? height;

  /// `FRAME-RATE`.
  final double? frameRate;

  /// `CODECS`, as written.
  final String? codecs;

  /// `NAME` or `VIDEO` label some platforms add (Twitch-style masters).
  final String? name;

  /// Video codec from [codecs]: `avc`, `hevc`, `av1`, or null when unknown.
  String? get videoCodec => hlsVideoCodec(codecs);

  /// Whether the variant carries no video (an audio-only rendition).
  bool get audioOnly {
    final list = codecs;
    if (list == null) return false;
    return list.split(',').every((codec) => codec.trim().startsWith('mp4a') || codec.trim().startsWith('ac-3'));
  }
}

/// The video codec named in an HLS `CODECS` attribute: `avc1`/`avc3` →
/// `avc`, `hvc1`/`hev1` → `hevc`, `av01` → `av1`; null when none is listed.
String? hlsVideoCodec(String? codecs) {
  if (codecs == null) return null;
  for (final raw in codecs.split(',')) {
    final codec = raw.trim().toLowerCase();
    if (codec.startsWith('avc1') || codec.startsWith('avc3')) return 'avc';
    if (codec.startsWith('hvc1') || codec.startsWith('hev1')) return 'hevc';
    if (codec.startsWith('av01')) return 'av1';
  }
  return null;
}

/// Parses HLS master playlists (RFC 8216 §4.3.4.2) for the adapters that
/// choose a variant themselves.
abstract final class HlsPlaylist {
  /// Whether [text] is an HLS playlist (`#EXTM3U` first).
  static bool isPlaylist(String text) => text.trimLeft().startsWith('#EXTM3U');

  /// Whether [text] is a master playlist (has `#EXT-X-STREAM-INF`).
  static bool isMaster(String text) => isPlaylist(text) && text.contains('#EXT-X-STREAM-INF:');

  /// The variants of master playlist [text] fetched from [source], in
  /// playlist order; URIs are resolved against [source]. Throws
  /// [FormatException] when [text] is not a playlist; a media playlist has
  /// no variants.
  static List<HlsVariant> variants(String text, {required Uri source}) {
    if (!isPlaylist(text)) throw const FormatException('Not an HLS playlist');
    final variants = <HlsVariant>[];
    Map<String, String>? pending;
    for (final raw in text.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        pending = attributes(line.substring('#EXT-X-STREAM-INF:'.length));
        continue;
      }
      if (line.startsWith('#')) continue;
      final attrs = pending;
      pending = null;
      if (attrs == null) continue;
      final resolution = RegExp(r'^(\d+)x(\d+)$').firstMatch(attrs['RESOLUTION'] ?? '');
      variants.add(
        HlsVariant(
          url: source.resolve(line),
          bandwidth: int.tryParse(attrs['BANDWIDTH'] ?? '') ?? 0,
          width: resolution == null ? null : int.parse(resolution.group(1)!),
          height: resolution == null ? null : int.parse(resolution.group(2)!),
          frameRate: double.tryParse(attrs['FRAME-RATE'] ?? ''),
          codecs: attrs['CODECS'],
          name: attrs['NAME'] ?? attrs['VIDEO'],
        ),
      );
    }
    return variants;
  }

  /// Attribute list of a tag (`KEY=value,KEY="quoted, value"`).
  static Map<String, String> attributes(String text) {
    final values = <String, String>{};
    for (final match in RegExp('([A-Z0-9-]+)=("[^"]*"|[^,]*)').allMatches(text)) {
      final value = match.group(2)!;
      values[match.group(1)!] = value.startsWith('"') && value.endsWith('"') && value.length >= 2
          ? value.substring(1, value.length - 1)
          : value;
    }
    return values;
  }
}
