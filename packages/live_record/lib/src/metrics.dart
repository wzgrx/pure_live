import 'dart:collection';
import 'dart:io';

import 'package:live_record/src/segments.dart';
import 'package:path/path.dart' as p;

/// Bytes of one attempt's segments, read from the files (3.x
/// `RecordingOutputTracker`): the segment muxer reports no size while the
/// files grow. Only the current segment and the next one are checked per
/// sample, so long recordings stay O(1).
final class SegmentMeter {
  /// Creates a meter of attempt [prefix] in [directory].
  new(this.directory, this.prefix);

  /// Directory of the segments.
  final String directory;

  /// Attempt prefix.
  final String prefix;

  var _index = 0;
  var _closedBytes = 0;

  /// Total bytes now.
  int sample() {
    var current = _size(_index);
    while (current != null && _size(_index + 1) != null) {
      _closedBytes += current;
      _index++;
      current = _size(_index);
    }
    return _closedBytes + (current ?? 0);
  }

  int? _size(int index) {
    if (index >= SegmentClock.maxSegments) return null;
    final file = File(p.join(directory, SegmentClock.segmentName(prefix, index)));
    try {
      return file.existsSync() ? file.lengthSync() : null;
    } on FileSystemException {
      return null;
    }
  }

  /// Bytes of every segment of [prefix] in [directory].
  static int measure(String directory, String prefix) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return 0;
    final files = selectAttemptSegments(dir.listSync(followLinks: false).whereType<File>(), filePrefix: prefix);
    var total = 0;
    for (final file in files) {
      try {
        total += file.lengthSync();
      } on FileSystemException {
        // Rotated away.
      }
    }
    return total;
  }

  /// Whether attempt [prefix] wrote any non-empty segment.
  static bool hasSegments(String directory, String prefix, {bool allowLegacy = false}) {
    final dir = Directory(directory);
    if (!dir.existsSync()) return false;
    try {
      final files = selectAttemptSegments(
        dir.listSync(followLinks: false).whereType<File>().where((file) => file.path.toLowerCase().endsWith('.ts')),
        filePrefix: prefix,
        allowLegacy: allowLegacy,
      );
      return files.any((file) => file.lengthSync() > 0);
    } on FileSystemException {
      return false;
    }
  }
}

/// Output bitrate from file growth over a sliding window (3.x
/// `RecordingBitrateWindow`): FFmpeg divides by the source timestamp and
/// showed a fraction of the real rate for live inputs.
final class BitrateWindow {
  /// Creates a window of [span].
  new({this.span = const Duration(seconds: 5)});

  /// Window length.
  final Duration span;

  final _samples = Queue<({int bytes, DateTime at})>();

  /// Adds a sample and returns kbit/s, or null until two samples span time.
  double? add(int bytes, DateTime at) {
    if (_samples.isNotEmpty && bytes < _samples.last.bytes) _samples.clear();
    _samples.addLast((bytes: bytes, at: at));
    while (_samples.length > 2 && at.difference(_samples.elementAt(1).at) >= span) {
      _samples.removeFirst();
    }
    final first = _samples.first;
    final elapsed = at.difference(first.at).inMilliseconds;
    if (elapsed <= 0 || bytes <= first.bytes) return null;
    return (bytes - first.bytes) * 8 / elapsed;
  }
}

/// Replaces one attempt's provisional segment bytes in [totalBytes] with its
/// committed MP4 size (3.x `reconcileFinalizedBytes`).
int reconcileFinalizedBytes({required int totalBytes, required int sourceBytes, required int finalizedBytes}) {
  final total = totalBytes.clamp(0, 1 << 62);
  final source = sourceBytes.clamp(0, 1 << 62);
  return (total > source ? total - source : 0) + finalizedBytes.clamp(0, 1 << 62);
}
