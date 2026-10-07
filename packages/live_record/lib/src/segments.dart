import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

final _prefixPattern = RegExp(r'^[A-Za-z0-9_-]+$');

/// The segment journal of one attempt (3.x `RecordingSegmentClock`,
/// "clock-v1"): FFmpeg's segment muxer writes `<prefix>_%06d.clock-v1.ts`
/// and a CSV of each segment's start on the reference clock; joining uses
/// those starts as exact durations, never the segments' own end times.
final class SegmentClock {
  new _(this.paths, this.starts);

  /// Validates journal [csv] against [segments]: one finished row per
  /// segment, names in order, the first start at zero, strictly increasing
  /// starts, one directory, no control characters. Anything else fails
  /// closed rather than guessing a duration or dropping a tail.
  ///
  /// [ignoredTail] names the empty segments dropped after the last of
  /// [segments] (H01.5): rows beyond [segments] are left out only when they
  /// are exactly the first of those names, in order, at the end.
  factory parse(
    String csv, {
    required String prefix,
    required List<String> segments,
    Iterable<String> ignoredTail = const [],
  }) {
    _checked(prefix);
    if (csv.length > maxBytes || segments.isEmpty || segments.length > maxSegments || !csv.endsWith('\n')) {
      throw const FormatException('Recording clock journal shape or unfinished row');
    }
    var rows = const LineSplitter().convert(csv);
    final tail = [for (final name in ignoredTail) p.basename(name)];
    final extra = rows.length - segments.length;
    if (extra > 0 && extra <= tail.length) {
      final dropped = rows.sublist(segments.length);
      var matches = true;
      for (var i = 0; i < extra; i++) {
        if (dropped[i].split(',').first != tail[i]) matches = false;
      }
      if (matches) rows = rows.sublist(0, segments.length);
    }
    if (rows.length != segments.length) throw const FormatException('Recording clock missing or extra segment');
    final starts = <int>[];
    final paths = <String>[];
    for (var i = 0; i < rows.length; i++) {
      final fields = rows[i].split(',');
      final expected = segmentName(prefix, i);
      if (fields.length != 3 || fields[0] != expected || p.basename(segments[i]) != expected) {
        throw const FormatException('Recording clock segment identity or order');
      }
      final start = _time(fields[1]);
      final end = _time(fields[2]);
      if ((i == 0 && start != 0) || (i > 0 && start <= starts.last) || end <= start) {
        throw const FormatException('Recording clock timestamp order');
      }
      starts.add(start);
      final path = p.absolute(segments[i]);
      if (RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)) throw const FormatException('Recording clock path controls');
      paths.add(path);
    }
    if (paths.map(p.dirname).toSet().length != 1) throw const FormatException('Recording clock mixed directories');
    return SegmentClock._(List.unmodifiable(paths), List.unmodifiable(starts));
  }

  /// Upper bound of a journal.
  static const int maxBytes = 8 * 1024 * 1024;

  /// Upper bound of segments per attempt.
  static const maxSegments = 100000;

  /// The profile is in every name, so a missing journal is never mistaken
  /// for a legacy recording.
  static const segmentSuffix = '.clock-v1.ts';

  /// Absolute segment paths, in order.
  final List<String> paths;

  /// Start of each segment, microseconds.
  final List<int> starts;

  /// FFmpeg output pattern of [prefix].
  static String segmentPattern(String prefix) => '${_checked(prefix)}_%06d$segmentSuffix';

  /// Name of segment [index] of [prefix].
  static String segmentName(String prefix, int index) {
    if (index < 0 || index >= maxSegments) throw const FormatException('Recording clock segment index');
    return '${_checked(prefix)}_${index.toString().padLeft(6, '0')}$segmentSuffix';
  }

  /// Journal name of [prefix].
  static String journalName(String prefix) => '${_checked(prefix)}.clock-v1.csv';

  static String _checked(String prefix) {
    if (prefix.isEmpty || prefix.length > 256 || !_prefixPattern.hasMatch(prefix)) {
      throw const FormatException('Recording clock attempt prefix');
    }
    return prefix;
  }

  /// Reads [file] (bounded) and validates it against [segments], leaving
  /// out the rows of an [ignoredTail] ([SegmentClock.parse]).
  static Future<SegmentClock> read(
    File file, {
    required String prefix,
    required List<File> segments,
    Iterable<File> ignoredTail = const [],
  }) async {
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      if (chunk.length > maxBytes - bytes.length) throw const FormatException('Recording clock journal budget');
      bytes.addAll(chunk);
    }
    return SegmentClock.parse(
      utf8.decode(bytes),
      prefix: prefix,
      segments: [for (final file in segments) file.path],
      ignoredTail: [for (final file in ignoredTail) file.path],
    );
  }

  static int _time(String value) {
    if (!RegExp(r'^\d{1,10}(?:\.\d{1,6})?$').hasMatch(value)) throw const FormatException('Recording clock timestamp');
    final parts = value.split('.');
    final micros = int.parse(parts[0]) * 1000000 + (parts.length == 1 ? 0 : int.parse(parts[1].padRight(6, '0')));
    if (micros > 9007199254740991) throw const FormatException('Recording clock timestamp range');
    return micros;
  }

  /// The concat manifest: every file with `inpoint 0` and, except the last,
  /// its duration up to the next start.
  String toConcatManifest() {
    final manifest = StringBuffer('ffconcat version 1.0\n');
    for (var i = 0; i < paths.length; i++) {
      manifest.writeln("file '${_escape(paths[i])}'\ninpoint 0");
      if (i + 1 < paths.length) {
        final duration = starts[i + 1] - starts[i];
        manifest.writeln('duration ${duration ~/ 1000000}.${(duration % 1000000).toString().padLeft(6, '0')}');
      }
    }
    return manifest.toString();
  }
}

/// The concat manifest of legacy segments (3.x schema 1 strftime names),
/// whose timestamps were normalized per segment already.
String legacyConcatManifest(Iterable<String> paths) {
  final manifest = StringBuffer('ffconcat version 1.0\n');
  for (final path in paths) {
    manifest.writeln("file '${_escape(path)}'");
  }
  return manifest.toString();
}

String _escape(String path) => path.replaceAll(r'\', '/').replaceAll("'", r"'\''");

/// The segments of attempt [filePrefix] among [candidates] (3.x
/// `selectAttemptSegments`): an attempt joins only its own files; legacy
/// unprefixed segments only with [allowLegacy] (recovery of a 3.x crash),
/// and never another attempt's clock-v1 files.
List<File> selectAttemptSegments(Iterable<File> candidates, {required String filePrefix, bool allowLegacy = false}) {
  final all = candidates.toList(growable: false);
  final matcher = RegExp('^${RegExp.escape(filePrefix)}_\\d{6,}(?:\\.clock-v1)?\\.ts\$', caseSensitive: false);
  final matching = all.where((file) => matcher.hasMatch(p.basename(file.path))).toList();
  if (matching.isNotEmpty) return matching;
  return allowLegacy
      ? all.where((file) => !file.path.toLowerCase().endsWith(SegmentClock.segmentSuffix)).toList()
      : <File>[];
}

/// Deletes what attempt [prefix] in [directory] left without recording
/// anything (H01.5): its empty segments, its journal when it is empty or
/// names no segment that is still there, then the directory when nothing
/// else is in it. Other attempts' files, chat XML and the user's files stay;
/// a failed deletion is left for later, never thrown.
void discardEmptyAttempt(String directory, String prefix) {
  final dir = Directory(directory);
  try {
    if (!dir.existsSync()) return;
    final journal = File(p.join(directory, SegmentClock.journalName(prefix)));
    final matcher = RegExp('^${RegExp.escape(prefix)}_\\d{6,}(?:\\.clock-v1)?\\.ts\$', caseSensitive: false);
    for (final entity in dir.listSync(followLinks: false)) {
      if (entity is! File || !matcher.hasMatch(p.basename(entity.path))) continue;
      try {
        if (entity.lengthSync() == 0) entity.deleteSync();
      } on FileSystemException {
        // Left for later.
      }
    }
    if (journal.existsSync()) {
      final length = journal.lengthSync();
      final rows = length == 0 || length > SegmentClock.maxBytes
          ? const <String>[]
          : const LineSplitter().convert(journal.readAsStringSync());
      final named = [
        for (final row in rows)
          if (row.trim().isNotEmpty) p.basename(row.split(',').first),
      ];
      if (length <= SegmentClock.maxBytes && named.every((name) => !File(p.join(directory, name)).existsSync())) {
        journal.deleteSync();
      }
    }
    if (dir.listSync(followLinks: false).isEmpty) dir.deleteSync();
  } on FileSystemException {
    // Left for later.
  } on FormatException {
    // Not an attempt prefix: nothing of it is touched.
  }
}

/// Ownership of a new clock-v1 output across FFmpeg's start (3.x
/// `RecordingClockReservation`): FFmpeg's `-n` does not protect the
/// journal, so a second writer of the same prefix in this process and any
/// existing journal or segment of it on disk are refused.
final class SegmentReservation {
  new _(this._key);

  static final _active = <String>{};
  final String _key;
  var _released = false;

  /// Reserves [prefix] in [directory].
  static Future<SegmentReservation> acquire(String directory, String prefix) async {
    final journal = p.normalize(p.absolute(p.join(directory, SegmentClock.journalName(prefix))));
    final key = Platform.isWindows ? journal.toLowerCase() : journal;
    if (!_active.add(key)) throw StateError('Recording clock output is already active');
    try {
      if (FileSystemEntity.typeSync(journal, followLinks: false) != FileSystemEntityType.notFound) {
        throw const FileSystemException('Recording clock output already exists');
      }
      final matcher = RegExp('^${RegExp.escape(prefix)}_\\d{6,}(?:\\.clock-v1)?\\.ts\$', caseSensitive: false);
      final parent = Directory(p.dirname(journal));
      if (parent.existsSync()) {
        await for (final entity in parent.list(followLinks: false)) {
          if (matcher.hasMatch(p.basename(entity.path))) {
            throw const FileSystemException('Recording clock segment already exists');
          }
        }
      }
      return SegmentReservation._(key);
    } on Object {
      _active.remove(key);
      rethrow;
    }
  }

  /// Releases the reservation; idempotent.
  void release() {
    if (_released) return;
    _released = true;
    _active.remove(_key);
  }
}
