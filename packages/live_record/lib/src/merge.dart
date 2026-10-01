import 'dart:async';
import 'dart:io';

import 'package:live_record/src/ffmpeg.dart';
import 'package:live_record/src/segments.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Why joining failed.
enum MergeFailure {
  /// The directory is gone.
  directoryMissing,

  /// No segment of the attempt.
  noSegments,

  /// The capture reported damaged packets; the source is kept.
  inputIntegrity,

  /// The clock-v1 journal is missing, partial or foreign.
  segmentClock,

  /// FFmpeg failed, timed out or produced nothing.
  ffmpeg,

  /// Cancelled.
  cancelled,
}

/// The outcome of joining one attempt.
@immutable
final class MergeResult {
  /// A joined attempt.
  const new done(String this.outputPath) : failure = null;

  /// A failed join; the segments stay.
  const new failed(MergeFailure this.failure) : outputPath = null;

  /// The MP4 file.
  final String? outputPath;

  /// Why it failed.
  final MergeFailure? failure;

  /// Whether the MP4 was committed.
  bool get ok => outputPath != null;
}

/// Joins an attempt's segments into `<prefix>.mp4` (3.x
/// `VideoProcessorService.convertToMp4`).
///
/// The journal (or, for 3.x's legacy segments, the names) gives the concat
/// manifest; FFmpeg copies into `<prefix>.mp4.partial` with `-xerror`; only
/// a clean exit with a non-empty file and no damage in the log renames it,
/// then the segments and journal are deleted. A damaged attempt is refused
/// up front so its source survives.
final class RecordMerger {
  /// Creates a merger running [runner].
  const new(this.runner);

  /// FFmpeg.
  final FfmpegRunner runner;

  /// Joins attempt [filePrefix] in [directory]. [recordedSeconds] scales the
  /// timeout; [allowLegacy] admits 3.x schema-1 segments (crash recovery);
  /// [damaged] refuses the join; [cancelled] is checked between steps.
  Future<MergeResult> merge({
    required String directory,
    required String filePrefix,
    int recordedSeconds = 0,
    bool allowLegacy = false,
    bool damaged = false,
    bool deleteSources = true,
    bool Function()? cancelled,
  }) async {
    bool isCancelled() => cancelled?.call() ?? false;
    if (damaged) return const MergeResult.failed(MergeFailure.inputIntegrity);
    final dir = Directory(directory);
    if (!dir.existsSync()) return const MergeResult.failed(MergeFailure.directoryMissing);
    final candidates = <File>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.ts') continue;
      try {
        // An empty clock-v1 tail is evidence of an unfinished attempt; keep it
        // so the journal check fails instead of silently dropping it.
        if (entity.lengthSync() <= 0 && !entity.path.toLowerCase().endsWith(SegmentClock.segmentSuffix)) continue;
        candidates.add(entity);
      } on FileSystemException {
        // Rotated away during the listing.
      }
    }
    final segments = selectAttemptSegments(candidates, filePrefix: filePrefix, allowLegacy: allowLegacy)
      ..sort((left, right) => p.basename(left.path).compareTo(p.basename(right.path)));
    if (segments.isEmpty) return const MergeResult.failed(MergeFailure.noSegments);
    final journal = File(p.join(directory, SegmentClock.journalName(filePrefix)));
    final usesClock =
        segments.any((file) => file.path.toLowerCase().endsWith(SegmentClock.segmentSuffix)) || journal.existsSync();
    final String manifest;
    if (usesClock) {
      try {
        if (segments.any((file) => file.lengthSync() <= 0)) {
          throw const FormatException('Recording clock empty segment');
        }
        manifest = (await SegmentClock.read(journal, prefix: filePrefix, segments: segments)).toConcatManifest();
      } on FileSystemException {
        return const MergeResult.failed(MergeFailure.segmentClock);
      } on FormatException {
        return const MergeResult.failed(MergeFailure.segmentClock);
      }
    } else {
      manifest = legacyConcatManifest([for (final file in segments) p.absolute(file.path)]);
    }
    var inputBytes = 0;
    for (final segment in segments) {
      try {
        inputBytes += segment.lengthSync();
      } on FileSystemException {
        // FFmpeg reports a vanished segment.
      }
    }
    if (isCancelled()) return const MergeResult.failed(MergeFailure.cancelled);
    final list = File(p.join(directory, '.$filePrefix.ffconcat'));
    var output = File(p.join(directory, '$filePrefix.mp4'));
    for (var suffix = 1; output.existsSync() || File('${output.path}.partial').existsSync(); suffix++) {
      output = File(p.join(directory, '$filePrefix-$suffix.mp4'));
    }
    final partial = File('${output.path}.partial');
    FfmpegExecution? execution;
    try {
      await list.writeAsString(manifest, flush: true);
      execution = await runner.start(FfmpegCommand.merge(manifest: list.path, output: partial.path));
      final logs = StringBuffer();
      final subscription = execution.logs.listen(logs.writeln);
      final int code;
      try {
        code = await execution.exitCode.timeout(mergeTimeout(inputBytes: inputBytes, recordedSeconds: recordedSeconds));
      } finally {
        await subscription.cancel();
      }
      if (isCancelled()) return const MergeResult.failed(MergeFailure.cancelled);
      if ((code != 0 && code != ffmpegEndOfFile) ||
          FfmpegMediaIntegrity.hasError(logs.toString()) ||
          !partial.existsSync() ||
          partial.lengthSync() <= 0) {
        return const MergeResult.failed(MergeFailure.ffmpeg);
      }
      await partial.rename(output.path);
      if (deleteSources) {
        var removedAll = true;
        for (final segment in segments) {
          try {
            if (segment.existsSync()) await segment.delete();
          } on FileSystemException {
            removedAll = false;
          }
        }
        // A locked segment keeps the journal for an exact later recovery.
        if (removedAll && journal.existsSync()) await journal.delete();
      }
      return MergeResult.done(output.path);
    } on TimeoutException {
      execution?.cancel();
      return const MergeResult.failed(MergeFailure.ffmpeg);
    } on FileSystemException {
      return const MergeResult.failed(MergeFailure.ffmpeg);
    } finally {
      for (final file in [list, partial]) {
        try {
          if (file.existsSync()) await file.delete();
        } on FileSystemException {
          // Never touch the source segments here.
        }
      }
    }
  }

  /// Join timeout (3.x `mergeTimeout`): 30 s to an hour, scaled by bytes
  /// (8 MiB/s floor) and duration.
  static Duration mergeTimeout({required int inputBytes, required int recordedSeconds}) {
    final bySize = (inputBytes.clamp(0, 1 << 62) / (8 * 1024 * 1024)).ceil() + 20;
    final byDuration = (recordedSeconds.clamp(0, 86400 * 30) / 20).ceil() + 20;
    return Duration(seconds: [30, bySize, byDuration].reduce((a, b) => a > b ? a : b).clamp(30, 3600));
  }
}
