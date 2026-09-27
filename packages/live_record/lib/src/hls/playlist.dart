import 'dart:typed_data';

import 'package:live_core/live_core.dart' show HlsPlaylist;
import 'package:meta/meta.dart';

/// An absolute byte range of a resource (`EXT-X-BYTERANGE`, the `BYTERANGE`
/// of `EXT-X-MAP`). Implicit offsets are resolved while parsing, so a range
/// never depends on the segment before it (REG-RECORD-029).
@immutable
final class M3u8ByteRange {
  /// Creates a range of [length] bytes from [offset].
  const new(this.offset, this.length);

  /// First byte.
  final int offset;

  /// Number of bytes.
  final int length;

  /// One past the last byte.
  int get end => offset + length;

  /// The `Range` request header value.
  String get header => 'bytes=$offset-${end - 1}';

  @override
  bool operator ==(Object other) => other is M3u8ByteRange && other.offset == offset && other.length == length;

  @override
  int get hashCode => Object.hash(offset, length);

  @override
  String toString() => '$length@$offset';
}

/// How media segments are encrypted (`EXT-X-KEY` `METHOD`).
enum M3u8KeyMethod {
  /// Not encrypted.
  none,

  /// Whole segments in AES-128-CBC with PKCS#7 padding.
  aes128,

  /// Samples encrypted inside the container (`SAMPLE-AES`, `SAMPLE-AES-CTR`)
  /// or a DRM key format: not recordable.
  unsupported,
}

/// The key in effect for a segment.
@immutable
final class M3u8Key {
  /// Creates a key description.
  const new({required this.method, this.uri, this.iv, this.detail = ''});

  /// No encryption.
  static const none = M3u8Key(method: M3u8KeyMethod.none);

  /// Method.
  final M3u8KeyMethod method;

  /// Where the 16-byte key is (absolute).
  final Uri? uri;

  /// Explicit initialisation vector (16 bytes); null: the media sequence number.
  final Uint8List? iv;

  /// The method and key format as the playlist spells them (for errors).
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is M3u8Key && other.method == method && other.uri == uri && _sameBytes(other.iv, iv);

  @override
  int get hashCode => Object.hash(method, uri, iv == null ? null : Object.hashAll(iv!));
}

/// The media initialisation section of fMP4 segments (`EXT-X-MAP`).
@immutable
final class M3u8Map {
  /// Creates a map.
  const new({required this.uri, this.range, this.key = M3u8Key.none});

  /// Where the initialisation section is (absolute).
  final Uri uri;

  /// Byte range inside [uri], if any.
  final M3u8ByteRange? range;

  /// The key in effect where the map appeared (the section may be encrypted).
  final M3u8Key key;

  @override
  bool operator ==(Object other) => other is M3u8Map && other.uri == uri && other.range == range && other.key == key;

  @override
  int get hashCode => Object.hash(uri, range, key);
}

/// One media segment of a media playlist.
@immutable
final class M3u8Segment {
  /// Creates a segment.
  const new({
    required this.sequence,
    required this.uri,
    required this.duration,
    this.range,
    this.key = M3u8Key.none,
    this.map,
    this.discontinuity = false,
    this.discontinuitySequence = 0,
    this.gap = false,
    this.title = '',
  });

  /// Media sequence number: the segment's identity within its feed (§7.4).
  final int sequence;

  /// Where the segment is (absolute).
  final Uri uri;

  /// `EXTINF` duration in seconds.
  final double duration;

  /// Byte range inside [uri], if any.
  final M3u8ByteRange? range;

  /// Encryption.
  final M3u8Key key;

  /// Initialisation section (fMP4), if any.
  final M3u8Map? map;

  /// Preceded by `EXT-X-DISCONTINUITY`.
  final bool discontinuity;

  /// Discontinuity sequence number of the segment.
  final int discontinuitySequence;

  /// Marked `EXT-X-GAP`: the server has no media for it.
  final bool gap;

  /// `EXTINF` title.
  final String title;

  /// [duration] in whole milliseconds.
  int get durationMs => (duration * 1000).round();
}

/// A variant stream of a master playlist (`EXT-X-STREAM-INF`).
@immutable
final class M3u8Variant {
  /// Creates a variant.
  const new({required this.uri, required this.bandwidth, this.codecs, this.resolution, this.audio, this.video});

  /// Media playlist (absolute).
  final Uri uri;

  /// `BANDWIDTH` in bit/s.
  final int bandwidth;

  /// `CODECS`.
  final String? codecs;

  /// `RESOLUTION` (`1920x1080`).
  final String? resolution;

  /// `AUDIO` group id.
  final String? audio;

  /// `VIDEO` group id.
  final String? video;
}

/// An alternative rendition of a master playlist (`EXT-X-MEDIA`).
@immutable
final class M3u8Rendition {
  /// Creates a rendition.
  const new({required this.type, required this.groupId, this.name, this.uri, this.isDefault = false});

  /// `AUDIO`, `VIDEO`, `SUBTITLES` or `CLOSED-CAPTIONS`.
  final String type;

  /// `GROUP-ID`.
  final String groupId;

  /// `NAME`.
  final String? name;

  /// Media playlist (absolute); null when the rendition is muxed into the variants.
  final Uri? uri;

  /// `DEFAULT=YES`.
  final bool isDefault;
}

/// A parsed playlist: [M3u8Master] or [M3u8Media].
sealed class M3u8Playlist {
  const new();

  /// Parses [text], resolving URIs against [base] (the playlist's final URL).
  /// Throws [FormatException] for anything that is not a usable playlist,
  /// including an LL-HLS delta update (`EXT-X-SKIP`): its segments cannot
  /// be numbered (REG-RECORD-027).
  static M3u8Playlist parse(String text, Uri base) => _Parser(base).parse(text);
}

/// A master playlist.
final class M3u8Master extends M3u8Playlist {
  /// Creates a master playlist.
  const new({required this.variants, required this.renditions});

  /// Variant streams in playlist order (I-frame playlists left out).
  final List<M3u8Variant> variants;

  /// Alternative renditions.
  final List<M3u8Rendition> renditions;

  /// The variant the recorder takes: the highest bandwidth, like the player
  /// (§7.1: the recorder follows the resolved line, never switches itself).
  M3u8Variant? get best {
    M3u8Variant? best;
    for (final variant in variants) {
      if (best == null || variant.bandwidth > best.bandwidth) best = variant;
    }
    return best;
  }

  /// Renditions of [variant]'s `AUDIO` group that have their own playlist
  /// (audio not muxed into the variant).
  List<M3u8Rendition> separateAudio(M3u8Variant variant) => [
    for (final rendition in renditions)
      if (rendition.type == 'AUDIO' && rendition.groupId == variant.audio && rendition.uri != null) rendition,
  ];
}

/// A media playlist.
final class M3u8Media extends M3u8Playlist {
  /// Creates a media playlist.
  const new({
    required this.targetDuration,
    required this.mediaSequence,
    required this.segments,
    this.discontinuitySequence = 0,
    this.endList = false,
    this.playlistType,
    this.hasParts = false,
    this.independentSegments = false,
  });

  /// `EXT-X-TARGETDURATION` in seconds (at least 1).
  final int targetDuration;

  /// `EXT-X-MEDIA-SEQUENCE`: number of the first segment.
  final int mediaSequence;

  /// `EXT-X-DISCONTINUITY-SEQUENCE`.
  final int discontinuitySequence;

  /// Complete segments in order. LL-HLS partial segments are not listed:
  /// only whole parent segments are recorded (REG-RECORD-028).
  final List<M3u8Segment> segments;

  /// `EXT-X-ENDLIST`: no more segments will be added.
  final bool endList;

  /// `EVENT`, `VOD` or null.
  final String? playlistType;

  /// Whether the playlist announced LL-HLS partial segments.
  final bool hasParts;

  /// `EXT-X-INDEPENDENT-SEGMENTS`.
  final bool independentSegments;

  /// Target duration as a [Duration].
  Duration get target => Duration(seconds: targetDuration);

  /// Sequence number of the last segment, or null when there is none.
  int? get lastSequence => segments.isEmpty ? null : segments.last.sequence;
}

final class _Parser {
  new(this.base);

  final Uri base;

  M3u8Playlist parse(String text) {
    var body = text;
    if (body.startsWith('﻿')) body = body.substring(1);
    final lines = body.split(RegExp(r'\r\n|\r|\n'));
    var index = 0;
    while (index < lines.length && lines[index].trim().isEmpty) {
      index++;
    }
    if (index >= lines.length || lines[index].trim() != '#EXTM3U') {
      throw const FormatException('not an HLS playlist (no #EXTM3U)');
    }
    final rest = [for (final line in lines.skip(index + 1)) line.trim()];
    final master = rest.any((line) => line.startsWith('#EXT-X-STREAM-INF:'));
    final media = rest.any((line) => line.startsWith('#EXTINF:'));
    if (master && !media) return _master(rest);
    return _media(rest);
  }

  Uri _resolve(String reference) {
    try {
      return base.resolve(reference);
    } on FormatException {
      throw FormatException('bad URI in the playlist: $reference');
    }
  }

  M3u8Master _master(List<String> lines) {
    final variants = <M3u8Variant>[];
    final renditions = <M3u8Rendition>[];
    Map<String, String>? pending;
    for (final line in lines) {
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        pending = HlsPlaylist.attributes(line.substring('#EXT-X-STREAM-INF:'.length));
      } else if (line.startsWith('#EXT-X-MEDIA:')) {
        final a = HlsPlaylist.attributes(line.substring('#EXT-X-MEDIA:'.length));
        final type = a['TYPE'];
        final group = a['GROUP-ID'];
        if (type == null || group == null) continue;
        final uri = a['URI'];
        renditions.add(
          M3u8Rendition(
            type: type,
            groupId: group,
            name: a['NAME'],
            uri: uri == null ? null : _resolve(uri),
            isDefault: a['DEFAULT'] == 'YES',
          ),
        );
      } else if (!line.startsWith('#')) {
        final attributes = pending;
        pending = null;
        if (attributes == null) continue;
        variants.add(
          M3u8Variant(
            uri: _resolve(line),
            bandwidth: int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0,
            codecs: attributes['CODECS'],
            resolution: attributes['RESOLUTION'],
            audio: attributes['AUDIO'],
            video: attributes['VIDEO'],
          ),
        );
      }
    }
    if (variants.isEmpty) throw const FormatException('master playlist without variants');
    return M3u8Master(variants: variants, renditions: renditions);
  }

  M3u8Media _media(List<String> lines) {
    int? target;
    var sequence = 0;
    var discontinuitySequence = 0;
    var ended = false;
    String? type;
    var parts = false;
    var independent = false;
    var sawSegment = false;

    // Pending state for the next segment.
    double? duration;
    var title = '';
    M3u8ByteRange? range;
    var discontinuity = false;
    var gap = false;
    // Keys in effect, by KEYFORMAT (several can apply at once).
    final keys = <String, M3u8Key>{};
    M3u8Map? map;
    M3u8Segment? previous;
    final segments = <M3u8Segment>[];
    var discontinuities = 0;

    M3u8Key currentKey() {
      if (keys.isEmpty) return M3u8Key.none;
      final identity = keys['identity'];
      if (identity != null) return identity;
      final other = keys.values.first;
      return M3u8Key(method: M3u8KeyMethod.unsupported, detail: other.detail);
    }

    for (final line in lines) {
      if (line.isEmpty) continue;
      if (!line.startsWith('#')) {
        final length = duration;
        if (length == null) continue; // A URI without EXTINF is not a segment.
        final uri = _resolve(line);
        var byteRange = range;
        if (byteRange != null && byteRange.offset < 0) {
          // Implicit offset: right after the previous segment of the same resource.
          final before = previous?.range;
          if (before == null || previous?.uri != uri) {
            throw const FormatException('EXT-X-BYTERANGE without an offset after a different resource');
          }
          byteRange = M3u8ByteRange(before.end, byteRange.length);
        }
        final segment = M3u8Segment(
          sequence: sequence + segments.length,
          uri: uri,
          duration: length,
          range: byteRange,
          key: currentKey(),
          map: map,
          discontinuity: discontinuity,
          discontinuitySequence: discontinuitySequence + discontinuities,
          gap: gap,
          title: title,
        );
        segments.add(segment);
        previous = segment;
        sawSegment = true;
        duration = null;
        title = '';
        range = null;
        discontinuity = false;
        gap = false;
        continue;
      }
      final colon = line.indexOf(':');
      final tag = colon < 0 ? line : line.substring(0, colon);
      final value = colon < 0 ? '' : line.substring(colon + 1);
      switch (tag) {
        case '#EXT-X-TARGETDURATION':
          target = _number(value, tag).ceil();
        case '#EXT-X-MEDIA-SEQUENCE':
          if (sawSegment) throw const FormatException('EXT-X-MEDIA-SEQUENCE after the first segment');
          sequence = _integer(value, tag);
        case '#EXT-X-DISCONTINUITY-SEQUENCE':
          if (sawSegment) throw const FormatException('EXT-X-DISCONTINUITY-SEQUENCE after the first segment');
          discontinuitySequence = _integer(value, tag);
        case '#EXTINF':
          final comma = value.indexOf(',');
          duration = _number(comma < 0 ? value : value.substring(0, comma), tag);
          title = comma < 0 ? '' : value.substring(comma + 1).trim();
        case '#EXT-X-BYTERANGE':
          range = _range(value);
        case '#EXT-X-DISCONTINUITY':
          discontinuity = true;
          discontinuities++;
        case '#EXT-X-GAP':
          gap = true;
        case '#EXT-X-KEY':
          final a = HlsPlaylist.attributes(value);
          final method = a['METHOD'] ?? 'NONE';
          final format = a['KEYFORMAT'] ?? 'identity';
          if (method == 'NONE') {
            keys.clear();
            continue;
          }
          final uri = a['URI'];
          final iv = a['IV'];
          keys[format] = M3u8Key(
            method: method == 'AES-128' && format == 'identity' ? M3u8KeyMethod.aes128 : M3u8KeyMethod.unsupported,
            uri: uri == null ? null : _resolve(uri),
            iv: iv == null ? null : _iv(iv),
            detail: format == 'identity' ? method : '$method ($format)',
          );
          if (keys[format]!.method == M3u8KeyMethod.aes128 && uri == null) {
            throw const FormatException('AES-128 key without URI');
          }
        case '#EXT-X-MAP':
          final a = HlsPlaylist.attributes(value);
          final uri = a['URI'];
          if (uri == null) throw const FormatException('EXT-X-MAP without URI');
          final byteRange = a['BYTERANGE'];
          M3u8ByteRange? mapRange;
          if (byteRange != null) {
            mapRange = _range(byteRange);
            if (mapRange.offset < 0) mapRange = M3u8ByteRange(0, mapRange.length);
          }
          map = M3u8Map(uri: _resolve(uri), range: mapRange, key: currentKey());
        case '#EXT-X-ENDLIST':
          ended = true;
        case '#EXT-X-PLAYLIST-TYPE':
          type = value.trim();
        case '#EXT-X-PART' || '#EXT-X-PART-INF' || '#EXT-X-PRELOAD-HINT':
          parts = true;
        case '#EXT-X-SKIP':
          throw const FormatException('LL-HLS delta update (EXT-X-SKIP): segments cannot be numbered');
        case '#EXT-X-INDEPENDENT-SEGMENTS':
          independent = true;
        case '#EXT-X-STREAM-INF':
          throw const FormatException('master and media tags in one playlist');
        default:
          // PROGRAM-DATE-TIME, DATERANGE, SERVER-CONTROL, platform tags
          // (Twitch prefetch hints): not needed to record the segments.
          break;
      }
    }
    var targetDuration = target;
    if (targetDuration == null) {
      if (segments.isEmpty) throw const FormatException('media playlist without EXT-X-TARGETDURATION');
      targetDuration = segments.fold<double>(0, (max, s) => s.duration > max ? s.duration : max).ceil();
    }
    return M3u8Media(
      targetDuration: targetDuration < 1 ? 1 : targetDuration,
      mediaSequence: sequence,
      discontinuitySequence: discontinuitySequence,
      segments: segments,
      endList: ended,
      playlistType: type,
      hasParts: parts,
      independentSegments: independent,
    );
  }

  static double _number(String value, String tag) {
    final number = double.tryParse(value.trim());
    if (number == null || number.isNaN || number < 0) throw FormatException('bad $tag value "$value"');
    return number;
  }

  static int _integer(String value, String tag) {
    final number = int.tryParse(value.trim());
    if (number == null || number < 0) throw FormatException('bad $tag value "$value"');
    return number;
  }

  /// `n[@o]`; a missing offset is returned as -1.
  static M3u8ByteRange _range(String value) {
    final parts = value.trim().split('@');
    final length = int.tryParse(parts.first);
    final offset = parts.length > 1 ? int.tryParse(parts[1]) : -1;
    if (length == null || length <= 0 || offset == null || parts.length > 2) {
      throw FormatException('bad byte range "$value"');
    }
    return M3u8ByteRange(offset, length);
  }

  static Uint8List _iv(String value) {
    final hex = value.startsWith('0x') || value.startsWith('0X') ? value.substring(2) : value;
    if (hex.isEmpty || hex.length > 32 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      throw FormatException('bad IV "$value"');
    }
    final padded = hex.padLeft(32, '0');
    return Uint8List.fromList([for (var i = 0; i < 16; i++) int.parse(padded.substring(2 * i, 2 * i + 2), radix: 16)]);
  }
}

bool _sameBytes(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
