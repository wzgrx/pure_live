import 'dart:convert';

/// Immutable request identity. Implicit ranges are resolved at parse time so
/// retiring the preceding segment never changes which bytes are requested.
final class HlsSegmentRange {
  const HlsSegmentRange(this.offset, this.length);
  final int offset;
  final int length;
  String get requestHeader => 'bytes=$offset-${offset + length - 1}';
  String get identity => '$length@$offset';
}

final class HlsKeyDescriptor {
  HlsKeyDescriptor(Map<String, String> attributes, this.uri) : attributes = Map.unmodifiable(attributes);
  final Map<String, String> attributes;
  final Uri? uri;
  String get format => attributes['KEYFORMAT'] ?? 'identity';
  String get identity => jsonEncode([
    {
      for (final key in (attributes.keys.toList()..sort()))
        if (key != 'URI') key: attributes[key],
    },
    uri?.toString(),
  ]);
}

final class HlsMapDescriptor {
  HlsMapDescriptor(this.uri, this.range, List<HlsKeyDescriptor> keys) : keys = List.unmodifiable(keys);
  final Uri uri;
  final HlsSegmentRange? range;
  // A later media-key rotation must not change the initialization key.
  final List<HlsKeyDescriptor> keys;
  String get identity => jsonEncode([uri.toString(), range?.identity, (keys.map((k) => k.identity).toList()..sort())]);
}

final class HlsSegmentDescriptor {
  HlsSegmentDescriptor({
    required this.sequence,
    required this.discontinuity,
    required this.uri,
    required this.duration,
    required this.extinf,
    required this.range,
    required this.initialization,
    required List<HlsKeyDescriptor> keys,
    required this.programTime,
    required this.explicitProgramTime,
    required this.gap,
  }) : keys = List.unmodifiable(keys);
  final int sequence;
  final int discontinuity;
  final Uri uri;
  final double duration;
  final String extinf;
  final HlsSegmentRange? range;
  final HlsMapDescriptor? initialization;
  final List<HlsKeyDescriptor> keys;
  final DateTime? programTime;
  final bool explicitProgramTime;
  final bool gap;
  String get identity => jsonEncode([
    sequence,
    discontinuity,
    uri.toString(),
    duration,
    range?.identity,
    initialization?.identity,
    (keys.map((k) => k.identity).toList()..sort()),
    gap,
  ]);
  int get retainedBytes => utf8.encode('$identity$extinf${programTime?.toIso8601String() ?? ''}').length;
}

/// Extraction for a future recording prefetch owner, not a playback parser or
/// a renderer. Unknown stateful tags stay explicit; delta playlists are rejected
/// rather than assigning incorrect media sequence numbers to their segments.
final class HlsMediaSnapshot {
  HlsMediaSnapshot._(
    this.source,
    this.targetDuration,
    this.ended,
    List<HlsSegmentDescriptor> segments,
    Set<String> unhandledTags,
  ) : segments = List.unmodifiable(segments),
      unhandledTags = Set.unmodifiable(unhandledTags);
  final Uri source;
  final int targetDuration;
  final bool ended;
  final List<HlsSegmentDescriptor> segments;
  final Set<String> unhandledTags;

  static HlsMediaSnapshot parse(String text, Uri source, {int maximumSegments = 512}) {
    if (maximumSegments < 1 || maximumSegments > 4096) throw ArgumentError.value(maximumSegments);
    if (text.length > 4 * 1024 * 1024 || utf8.encode(text).length > 4 * 1024 * 1024) {
      throw const FormatException('HLS snapshot exceeds text limit');
    }
    if (!const {'http', 'https'}.contains(source.scheme) || source.host.isEmpty) {
      throw const FormatException('HLS snapshot needs an HTTP source');
    }
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty || lines.first != '#EXTM3U') throw const FormatException('Missing HLS header');
    var sequence = 0;
    var discontinuity = 0;
    int? target;
    var ended = false;
    var gap = false;
    var sawDiscontinuity = false;
    var explicitTime = false;
    DateTime? time;
    double? duration;
    String? extinf;
    String? rangeText;
    HlsMapDescriptor? initialization;
    HlsSegmentDescriptor? previous;
    final keys = <String, HlsKeyDescriptor>{};
    final segments = <HlsSegmentDescriptor>[];
    final singletons = <String>{};
    final unhandled = <String>{};
    for (final raw in lines.skip(1)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final tag = line.split(':').first;
      final value = line.contains(':') ? line.substring(line.indexOf(':') + 1) : '';
      if (const {'#EXT-X-STREAM-INF', '#EXT-X-MEDIA', '#EXT-X-I-FRAME-STREAM-INF', '#EXT-X-SKIP'}.contains(tag)) {
        throw const FormatException('Master or delta input is not a complete media snapshot');
      }
      if (const {
        '#EXT-X-MEDIA-SEQUENCE',
        '#EXT-X-DISCONTINUITY-SEQUENCE',
        '#EXT-X-TARGETDURATION',
        '#EXT-X-VERSION',
        '#EXT-X-ENDLIST',
        '#EXT-X-PLAYLIST-TYPE',
      }.contains(tag)) {
        if (!singletons.add(tag)) throw const FormatException('Duplicate playlist property');
      }
      switch (tag) {
        case '#EXT-X-MEDIA-SEQUENCE':
          if (segments.isNotEmpty) throw const FormatException('Late media sequence');
          sequence = _unsigned(value);
        case '#EXT-X-DISCONTINUITY-SEQUENCE':
          if (segments.isNotEmpty || sawDiscontinuity) throw const FormatException('Late discontinuity sequence');
          discontinuity = _unsigned(value);
        case '#EXT-X-TARGETDURATION':
          target = _unsigned(value);
          if (target == 0 || target > 86400) throw const FormatException('Invalid target duration');
        case '#EXT-X-DISCONTINUITY':
          discontinuity = _checkedAdd(discontinuity, 1);
          sawDiscontinuity = true;
          // An explicit anchor already encountered applies to the upcoming
          // segment too; only an inferred time is invalidated by this tag.
          if (!explicitTime) time = null;
        case '#EXT-X-PROGRAM-DATE-TIME':
          time = _programTime(value);
          explicitTime = true;
        case '#EXTINF':
          if (duration != null) throw const FormatException('Missing segment URI');
          final durationText = value.split(',').first;
          if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(durationText)) {
            throw const FormatException('Invalid decimal duration');
          }
          duration = double.tryParse(durationText);
          if (duration == null || !duration.isFinite || duration <= 0 || duration > 86400) {
            throw const FormatException('Invalid segment duration');
          }
          extinf = line;
        case '#EXT-X-BYTERANGE':
          if (rangeText != null) throw const FormatException('Duplicate segment range');
          rangeText = value;
        case '#EXT-X-KEY':
          final attributes = _attributes(value);
          final method = attributes['METHOD'];
          if (method == 'NONE') {
            if (attributes.length != 1) throw const FormatException('NONE key has extra attributes');
            keys.clear();
          } else {
            if (method == null || method.isEmpty || attributes['URI'] == null) {
              throw const FormatException('Incomplete key descriptor');
            }
            final key = HlsKeyDescriptor(attributes, _resolve(source, attributes['URI']!));
            keys[key.format] = key;
            if (keys.length > 16) throw const FormatException('Too many key formats');
          }
        case '#EXT-X-MAP':
          final attributes = _attributes(value);
          if (attributes['URI'] == null) throw const FormatException('Missing initialization URI');
          final uri = _resolve(source, attributes['URI']!);
          final textRange = attributes['BYTERANGE'];
          // Do not invent an offset for a map with an omitted, ambiguous base.
          final range = textRange == null ? null : _range(textRange, uri, null);
          if (keys.values.any((key) => key.attributes['METHOD'] == 'AES-128' && key.attributes['IV'] == null)) {
            throw const FormatException('Encrypted initialization requires an IV');
          }
          initialization = HlsMapDescriptor(uri, range, keys.values.toList());
        case '#EXT-X-GAP':
          gap = true;
        case '#EXT-X-ENDLIST':
          ended = true;
        case '#EXT-X-VERSION':
          if (_unsigned(value) == 0) throw const FormatException('Invalid HLS version');
        case '#EXT-X-INDEPENDENT-SEGMENTS':
          break;
        default:
          if (line.startsWith('#')) {
            if (line.startsWith('#EXT')) unhandled.add(tag);
            continue;
          }
          if (ended || duration == null) throw const FormatException('Unexpected media URI');
          if (segments.length >= maximumSegments) throw const FormatException('Too many HLS segments');
          final uri = _resolve(source, line);
          final range = rangeText == null ? null : _range(rangeText, uri, previous);
          final segment = HlsSegmentDescriptor(
            sequence: sequence,
            discontinuity: discontinuity,
            uri: uri,
            duration: duration,
            extinf: extinf!,
            range: range,
            initialization: initialization,
            keys: keys.values.toList(),
            programTime: time,
            explicitProgramTime: explicitTime,
            gap: gap,
          );
          if (segment.retainedBytes > 64 * 1024) {
            throw const FormatException('Segment dependency metadata exceeds limit');
          }
          segments.add(segment);
          previous = segment;
          sequence = _checkedAdd(sequence, 1);
          time = time?.add(Duration(microseconds: (duration * 1000000).round()));
          duration = null;
          extinf = null;
          rangeText = null;
          gap = false;
          explicitTime = false;
      }
    }
    if (target == null || duration != null || rangeText != null || gap) {
      throw const FormatException('Incomplete media snapshot');
    }
    if (segments.any((segment) => segment.duration.round() > target!)) {
      throw const FormatException('Segment exceeds target duration');
    }
    return HlsMediaSnapshot._(source, target, ended, segments, unhandled);
  }
}

/// Metadata only. One instance belongs to one selected media playlist and one
/// source generation. A failed refresh is atomic; evictions are explicit and
/// are not evidence that media was downloaded or that the consumer received it.
final class HlsRetainedWindow {
  HlsRetainedWindow(this.source, {this.maximumSegments = 64, this.maximumBytes = 1024 * 1024}) {
    if (maximumSegments < 1 || maximumSegments > 512 || maximumBytes < 1 || maximumBytes > 8 * 1024 * 1024) {
      throw ArgumentError('Invalid HLS retention budget');
    }
  }
  final Uri source;
  final int maximumSegments;
  final int maximumBytes;
  List<HlsSegmentDescriptor> _segments = const [];
  List<HlsSegmentDescriptor> get segments => _segments;
  int _latestFirst = -1;
  bool _ended = false;
  int? _targetDuration;
  bool get ended => _ended;
  int get retainedBytes => _segments.fold(0, (sum, segment) => sum + segment.retainedBytes);

  List<HlsSegmentDescriptor> merge(HlsMediaSnapshot snapshot) {
    if (snapshot.source != source || snapshot.unhandledTags.isNotEmpty) {
      throw const FormatException('Snapshot identity or tag contract differs');
    }
    if (_targetDuration != null && _targetDuration != snapshot.targetDuration) {
      throw const FormatException('Target duration changed within a source generation');
    }
    final incoming = snapshot.segments;
    if (incoming.isEmpty) {
      if (_segments.isNotEmpty || (_ended && !snapshot.ended)) {
        throw const FormatException('Empty refresh of a retained window');
      }
      _targetDuration = snapshot.targetDuration;
      _ended = snapshot.ended;
      return const [];
    }
    if (incoming.first.sequence < _latestFirst ||
        (_segments.isNotEmpty && incoming.last.sequence < _segments.last.sequence) ||
        (_ended && !snapshot.ended)) {
      throw const FormatException('Stale or reopened HLS window');
    }
    final merged = {for (final segment in _segments) segment.sequence: segment};
    for (final segment in incoming) {
      final existing = merged[segment.sequence];
      if (existing != null &&
          (existing.identity != segment.identity ||
              (existing.programTime != null &&
                  segment.programTime != null &&
                  existing.programTime != segment.programTime))) {
        throw const FormatException('Conflicting HLS segment identity');
      }
      if (_ended && existing == null) throw const FormatException('Ended window grew');
      merged[segment.sequence] = existing ?? segment;
    }
    final values = merged.values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
    for (var i = 1; i < values.length; i++) {
      if (values[i].sequence != values[i - 1].sequence + 1) {
        throw const FormatException('Missing HLS sequence interval');
      }
    }
    if (values.any((segment) => segment.retainedBytes > maximumBytes)) {
      throw const FormatException('A segment exceeds retention metadata budget');
    }
    var bytes = values.fold<int>(0, (sum, segment) => sum + segment.retainedBytes);
    final evicted = <HlsSegmentDescriptor>[];
    while (values.length > maximumSegments || bytes > maximumBytes) {
      final segment = values.removeAt(0);
      bytes -= segment.retainedBytes;
      evicted.add(segment);
    }
    _segments = List.unmodifiable(values);
    _latestFirst = incoming.first.sequence;
    _targetDuration = snapshot.targetDuration;
    _ended = snapshot.ended;
    return List.unmodifiable(evicted);
  }
}

const _maximumInteger = 0x7fffffffffffffff;
int _unsigned(String value) {
  if (!RegExp(r'^\d{1,19}$').hasMatch(value)) throw const FormatException('Invalid HLS integer');
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) throw const FormatException('HLS integer overflow');
  return parsed;
}

int _checkedAdd(int a, int b) {
  if (a > _maximumInteger - b) throw const FormatException('HLS integer overflow');
  return a + b;
}

Uri _resolve(Uri base, String value) {
  final uri = base.resolve(value);
  if (value.isEmpty || !const {'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty || uri.hasFragment) {
    throw const FormatException('Unsupported HLS resource URI');
  }
  return uri;
}

HlsSegmentRange _range(String value, Uri uri, HlsSegmentDescriptor? previous) {
  final parts = value.split('@');
  if (parts.length > 2) throw const FormatException('Invalid byte range');
  final length = _unsigned(parts.first);
  if (length == 0) throw const FormatException('Empty byte range');
  final int offset;
  if (parts.length == 2) {
    offset = _unsigned(parts.last);
  } else {
    if (previous?.uri != uri || previous?.range == null) throw const FormatException('Ambiguous range offset');
    offset = _checkedAdd(previous!.range!.offset, previous.range!.length);
  }
  _checkedAdd(offset, length);
  return HlsSegmentRange(offset, length);
}

Map<String, String> _attributes(String value) {
  final attributes = <String, String>{};
  final pattern = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,\s"]+)');
  var offset = 0;
  while (offset < value.length) {
    final match = pattern.matchAsPrefix(value, offset);
    if (match == null || attributes.containsKey(match.group(1))) throw const FormatException('Invalid HLS attributes');
    var text = match.group(2)!;
    if (text.startsWith('"')) text = text.substring(1, text.length - 1);
    attributes[match.group(1)!] = text;
    offset = match.end;
    if (offset == value.length) break;
    if (value[offset++] != ',' || offset == value.length) throw const FormatException('Invalid attribute separator');
  }
  return attributes;
}

DateTime _programTime(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,9})?(Z|[+-](\d{2}):(\d{2}))$')
      .firstMatch(value);
  if (match == null) throw const FormatException('Program time requires a complete date and timezone');
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final date = DateTime.utc(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5]);
  if (date.year != parts[0] ||
      date.month != parts[1] ||
      date.day != parts[2] ||
      date.hour != parts[3] ||
      date.minute != parts[4] ||
      date.second != parts[5] ||
      (match.group(8) != null && (int.parse(match.group(8)!) > 23 || int.parse(match.group(9)!) > 59))) {
    throw const FormatException('Invalid calendar time or timezone');
  }
  return DateTime.parse(value).toUtc();
}
