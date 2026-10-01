import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Limits of the HLS prefetch and retained window (recording, M8.1; 3.x
/// `HlsPrefetchScheduler`, `HlsPrefetchPool` and `HlsRetainedWindow`).
@immutable
final class HlsPrefetchOptions {
  /// Creates the limits.
  const new({
    this.maxSegments = 48,
    this.maxBytes = 96 << 20,
    this.maxSegmentBytes = 32 << 20,
    this.concurrency = 4,
    this.idlePolls = 12,
  });

  /// Segments kept listed behind the upstream window (3.x: 64).
  final int maxSegments;

  /// Bytes of downloaded, not yet delivered segments held in memory per
  /// media playlist; above it new segments are left to the engine.
  final int maxBytes;

  /// A larger segment is not held (the engine fetches it itself).
  final int maxSegmentBytes;

  /// Parallel segment downloads per media playlist.
  final int concurrency;

  /// Polls without the reader asking for the playlist or a segment after
  /// which prefetching stops (the reader went away).
  final int idlePolls;
}

/// One segment of a media playlist as the window keeps it.
final class _Segment {
  new({
    required this.sequence,
    required this.url,
    required this.tags,
    required this.key,
    required this.map,
    required this.discontinuity,
    required this.cacheable,
  });

  final int sequence;
  final Uri url;

  /// Its own tags in order (`#EXTINF`, `#EXT-X-DISCONTINUITY`,
  /// `#EXT-X-PROGRAM-DATE-TIME`, `#EXT-X-DATERANGE`, ...).
  final List<String> tags;

  /// The `#EXT-X-KEY` lines and `#EXT-X-MAP` line in force for it, with
  /// absolute URIs.
  final List<String> key;
  final String? map;

  /// Its discontinuity sequence number.
  final int discontinuity;

  /// Whether its body may be held (not a byte range, not a gap).
  final bool cacheable;

  Future<Uint8List?>? body;
  int bytes = 0;
  bool failed = false;

  bool get starts => tags.contains('#EXT-X-DISCONTINUITY');
}

/// A parsed media playlist.
final class _Snapshot {
  new(this.segments, this.header, {required this.targetSeconds, required this.ended});

  final List<_Segment> segments;

  /// `#EXT-X-VERSION`, `#EXT-X-INDEPENDENT-SEGMENTS`, `#EXT-X-PLAYLIST-TYPE`,
  /// `#EXT-X-START` lines kept as they were.
  final List<String> header;
  final int targetSeconds;
  final bool ended;
}

/// Fetches one URL of the line (the route's headers, cookies and session
/// cookies apply).
typedef HlsWindowFetch = Future<({int status, Uri url, Stream<List<int>> body})> Function(Uri url);

/// Keeps one live media playlist complete for a slow reader: the segments
/// of every playlist the relay saw stay listed (up to
/// [HlsPrefetchOptions.maxSegments]) until the reader took them, and while
/// the reader reads this playlist its new segments are downloaded in
/// parallel as soon as they appear, polled at half the target duration
/// independently of the reader.
///
/// FFmpeg reads an HLS input one segment at a time and reloads the playlist
/// only after the segments it has; a CDN that is slow per request (overseas
/// platforms behind a proxy) or a short live window (low-latency HLS, 2 s
/// segments) then lets segments leave the playlist before FFmpeg asks for
/// them ("skipping N segments ahead, expired from playlists"), and the CDN
/// deletes them soon after. 3.x solved this with a prefetch pool and a
/// retained manifest (about 2900 lines); this is the same idea in one
/// class:
///
/// - the served playlist starts at the segment before the next one the
///   reader needs, so an expired segment the window still knows is listed;
/// - low-latency parts, preload hints and rendition reports are left out
///   (FFmpeg reads whole segments), date ranges and program dates stay with
///   their segment, keys and maps are repeated where they change;
/// - bodies are held in memory up to [HlsPrefetchOptions.maxBytes]; above
///   it, or when a download fails, the reader fetches upstream itself as
///   before;
/// - a sequence that goes back (a restarted stream) starts the window over.
final class HlsMediaWindow {
  /// Creates the window; `source` is the playlist's current upstream
  /// address (it changes on renewal), `resolve` turns a reference into the
  /// absolute URL the relay requests (token propagation included).
  new({required this.options, required this._source, required this._resolve, required this._fetch});

  /// Limits.
  final HlsPrefetchOptions options;

  final Uri Function() _source;
  final Uri? Function(Uri base, String reference) _resolve;
  final HlsWindowFetch _fetch;
  final _known = <int, _Segment>{};
  final _byUrl = <String, _Segment>{};
  final _downloadsInFlight = <StreamSubscription<List<int>>, Completer<void>>{};
  _Snapshot? _last;
  int? _next;
  var _serves = 0;
  var _active = false;
  var _idle = 0;
  var _downloads = 0;
  var _closed = false;
  Timer? _poll;

  /// Whether new segments are being downloaded.
  bool get prefetching => _active && !_closed;

  /// Segments listed now (tests, diagnostics).
  int get knownSegments => _known.length;

  /// Bytes held now.
  int get heldBytes => _known.values.fold(0, (sum, segment) => sum + segment.bytes);

  /// Merges a playlist fetched for the reader and returns the playlist the
  /// reader gets: [text] when it is not a live media playlist this window
  /// can keep, else the retained window with absolute URLs.
  ///
  /// Prefetching starts once the reader reloads the playlist after taking a
  /// segment: FFmpeg probes the first segments of every variant of a master
  /// but reloads only the ones it records.
  String serve(String text, Uri base) {
    if (_closed) return text;
    _serves++;
    _idle = 0;
    final snapshot = _merge(text, base);
    if (snapshot == null) return text;
    _activate();
    return _render(snapshot);
  }

  /// Whether [url] is a segment of this playlist.
  bool owns(Uri url) => _byUrl.containsKey('$url');

  /// The held body of the segment at [url] (waiting for its download), or
  /// null when the reader should fetch it upstream. Marks it delivered.
  Future<Uint8List?> take(Uri url) async {
    final segment = _byUrl['$url'];
    if (segment == null || _closed) return null;
    _delivered(segment.sequence);
    final body = segment.body;
    if (body == null) return null;
    final bytes = await body;
    return _closed ? null : bytes;
  }

  void _delivered(int sequence) {
    _idle = 0;
    final next = _next;
    if (next == null || sequence + 1 > next) _next = sequence + 1;
    // The delivered one stays for a retry; older ones go.
    for (final old in _known.values.where((segment) => segment.sequence < sequence && segment.body != null).toList()) {
      old
        ..body = null
        ..bytes = 0;
    }
    _activate();
    _download();
  }

  void _activate() {
    if (_active || _closed || _next == null || _serves < 2) return;
    _active = true;
    _schedulePoll();
    _download();
  }

  _Snapshot? _merge(String text, Uri base) {
    final snapshot = _parse(text, base);
    if (snapshot == null || snapshot.segments.isEmpty) return null;
    final first = snapshot.segments.first.sequence;
    final last = snapshot.segments.last.sequence;
    final next = _next;
    final known = _known.isEmpty ? null : _known.keys.reduce((a, b) => a > b ? a : b);
    if ((next != null && last < next - 2) || (known != null && last < known - options.maxSegments)) {
      // The sequence went back: another stream.
      _reset();
    }
    for (final segment in snapshot.segments) {
      final existing = _known[segment.sequence];
      if (existing != null && (existing.url == segment.url || existing.body != null)) continue;
      if (existing != null) _byUrl.remove('${existing.url}');
      _known[segment.sequence] = segment;
      _byUrl['${segment.url}'] = segment;
    }
    // Forget what the reader passed and what exceeds the window; the
    // current upstream window always stays.
    final floor = math.min(
      first,
      [if (_next case final next?) next - 1, last - options.maxSegments + 1].reduce(math.max),
    );
    for (final sequence in _known.keys.where((sequence) => sequence < floor).toList()) {
      final dropped = _known.remove(sequence)!;
      _byUrl.remove('${dropped.url}');
    }
    _last = snapshot;
    if (_active) _download();
    return snapshot;
  }

  String _render(_Snapshot snapshot) {
    final last = snapshot.segments.last.sequence;
    // Back from the newest over the known segments: to the one before the
    // reader's next (an expired segment it still needs stays listed), or to
    // the upstream window before the reader started.
    final limit = _next == null ? snapshot.segments.first.sequence : _next! - 1;
    var start = last;
    while (start > limit && _known.containsKey(start - 1)) {
      start--;
    }
    final out = StringBuffer('#EXTM3U\n');
    final first = _known[start]!;
    snapshot.header.forEach(out.writeln);
    out
      ..writeln('#EXT-X-TARGETDURATION:${snapshot.targetSeconds}')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:$start')
      ..writeln('#EXT-X-DISCONTINUITY-SEQUENCE:${first.discontinuity}');
    List<String>? key;
    String? map;
    for (var sequence = start; sequence <= last; sequence++) {
      final segment = _known[sequence]!;
      if (key == null || !_sameLines(key, segment.key)) {
        key = segment.key;
        // A key in force before the window starts is restated; a key that
        // ends is closed with METHOD=NONE.
        if (segment.key.isEmpty && sequence != start) {
          out.writeln('#EXT-X-KEY:METHOD=NONE');
        } else {
          segment.key.forEach(out.writeln);
        }
      }
      if (segment.map != map) {
        map = segment.map;
        if (map != null) out.writeln(map);
      }
      for (final tag in segment.tags) {
        if (sequence == start && tag == '#EXT-X-DISCONTINUITY') continue;
        out.writeln(tag);
      }
      out.writeln(segment.url);
    }
    if (snapshot.ended) out.writeln('#EXT-X-ENDLIST');
    return out.toString();
  }

  static bool _sameLines(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  static final _uriAttribute = RegExp('URI="([^"]*)"');

  _Snapshot? _parse(String text, Uri base) {
    if (text.contains('#EXT-X-STREAM-INF') || text.contains('#EXT-X-I-FRAMES-ONLY') || text.contains('#EXT-X-SKIP')) {
      return null;
    }
    var sequence = 0;
    var discontinuity = 0;
    var target = 0;
    var ended = false;
    final header = <String>[];
    final segments = <_Segment>[];
    var tags = <String>[];
    var key = <String>[];
    var keyContinues = false;
    String? map;
    String absolute(String line) => line.replaceFirstMapped(_uriAttribute, (match) {
      final url = _resolve(base, match.group(1)!);
      return url == null ? match.group(0)! : 'URI="$url"';
    });
    int? number(String line) => int.tryParse(line.substring(line.indexOf(':') + 1).trim());
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line == '#EXTM3U') continue;
      final wasKey = keyContinues;
      keyContinues = false;
      if (!line.startsWith('#')) {
        final url = _resolve(base, line);
        if (url == null) return null;
        final starts = tags.contains('#EXT-X-DISCONTINUITY');
        if (starts) discontinuity++;
        segments.add(
          _Segment(
            sequence: sequence++,
            url: url,
            tags: tags,
            key: key,
            map: map,
            discontinuity: discontinuity,
            cacheable: !tags.any((tag) => tag.startsWith('#EXT-X-BYTERANGE') || tag == '#EXT-X-GAP'),
          ),
        );
        tags = [];
        continue;
      }
      final name = line.contains(':') ? line.substring(0, line.indexOf(':')) : line;
      switch (name) {
        case '#EXT-X-MEDIA-SEQUENCE':
          sequence = number(line) ?? 0;
        case '#EXT-X-DISCONTINUITY-SEQUENCE':
          discontinuity = number(line) ?? 0;
        case '#EXT-X-TARGETDURATION':
          target = number(line) ?? 0;
        case '#EXT-X-ENDLIST':
          ended = true;
        case '#EXT-X-VERSION' || '#EXT-X-INDEPENDENT-SEGMENTS' || '#EXT-X-PLAYLIST-TYPE' || '#EXT-X-START':
          if (segments.isEmpty && tags.isEmpty) header.add(line);
        case '#EXT-X-KEY':
          // Consecutive keys (several KEYFORMATs) apply together.
          key = [if (wasKey) ...key, absolute(line)];
          keyContinues = true;
        case '#EXT-X-MAP':
          map = absolute(line);
        case '#EXT-X-PART' ||
            '#EXT-X-PART-INF' ||
            '#EXT-X-PRELOAD-HINT' ||
            '#EXT-X-RENDITION-REPORT' ||
            '#EXT-X-SERVER-CONTROL':
          // Low-latency parts: the reader takes whole segments.
          break;
        case '#EXTINF' ||
            '#EXT-X-DISCONTINUITY' ||
            '#EXT-X-PROGRAM-DATE-TIME' ||
            '#EXT-X-DATERANGE' ||
            '#EXT-X-BYTERANGE' ||
            '#EXT-X-GAP' ||
            '#EXT-X-BITRATE':
          tags.add(line);
        default:
          // Other tags travel with the next segment, unknown ones as they
          // were.
          if (name.startsWith('#EXT')) tags.add(line);
      }
    }
    if (target <= 0 || (ended && segments.isEmpty)) return null;
    return _Snapshot(segments, header, targetSeconds: target, ended: ended);
  }

  void _download() {
    final next = _next;
    if (_closed || !_active || next == null) return;
    final held = heldBytes;
    for (final sequence in _known.keys.toList()..sort()) {
      if (_downloads >= options.concurrency || held >= options.maxBytes) return;
      final segment = _known[sequence]!;
      if (sequence < next || !segment.cacheable || segment.body != null || segment.failed) continue;
      _downloads++;
      segment.body = _get(segment).whenComplete(() {
        _downloads--;
        if (!_closed) _download();
      });
    }
  }

  Future<Uint8List?> _get(_Segment segment) async {
    try {
      final answer = await _fetch(segment.url);
      if (answer.status != 200) {
        unawaited(answer.body.drain<void>().catchError((Object _) {}));
        throw StateError('upstream ${answer.status}');
      }
      final builder = BytesBuilder(copy: false);
      final done = Completer<void>();
      late final StreamSubscription<List<int>> subscription;
      subscription = answer.body.listen(
        (chunk) {
          builder.add(chunk);
          if (builder.length > options.maxSegmentBytes) {
            unawaited(subscription.cancel());
            if (!done.isCompleted) done.completeError(StateError('segment too large'));
          }
        },
        onError: (Object error) {
          if (!done.isCompleted) done.completeError(error);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      _downloadsInFlight[subscription] = done;
      try {
        await done.future;
      } finally {
        _downloadsInFlight.remove(subscription);
      }
      if (_closed) return null;
      final bytes = builder.takeBytes();
      segment.bytes = bytes.length;
      return bytes;
    } on Object {
      segment
        ..failed = true
        ..bytes = 0;
      return null;
    }
  }

  void _schedulePoll() {
    _poll?.cancel();
    final seconds = (_last?.targetSeconds ?? 2) / 2;
    final wait = Duration(milliseconds: (seconds.clamp(1, 6) * 1000).round());
    _poll = Timer(wait, () => unawaited(_pollNow()));
  }

  Future<void> _pollNow() async {
    if (_closed || !_active) return;
    if (++_idle > options.idlePolls) {
      // The reader stopped reading this playlist (a discarded variant).
      _active = false;
      for (final segment in _known.values) {
        segment
          ..body = null
          ..bytes = 0;
      }
      return;
    }
    try {
      final answer = await _fetch(_source());
      final body = await utf8.decoder.bind(answer.body.take(4096)).join();
      if (answer.status == 200 && !_closed) _merge(body, answer.url);
    } on Object {
      // The reader's own reload still works; poll again later.
    }
    if (!_closed && _active) _schedulePoll();
  }

  void _reset() {
    _known.clear();
    _byUrl.clear();
    _next = null;
    _active = false;
    _poll?.cancel();
  }

  /// Stops polling and downloads and drops the held bodies.
  void close() {
    _closed = true;
    _poll?.cancel();
    for (final MapEntry(key: subscription, value: done) in _downloadsInFlight.entries.toList()) {
      unawaited(subscription.cancel());
      if (!done.isCompleted) done.completeError(StateError('closed'));
    }
    _downloadsInFlight.clear();
    _known.clear();
    _byUrl.clear();
  }
}
