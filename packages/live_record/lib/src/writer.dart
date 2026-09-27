import 'dart:async';

import 'package:live_record/src/errors.dart';
import 'package:live_record/src/gaps.dart';
import 'package:path/path.dart' as p;

/// One output file of a session.
final class RecordedSegment {
  /// Creates segment [index] planned at [plannedPath].
  new(this.index, this.plannedPath);

  /// 1-based segment number.
  final int index;

  /// Path the segment was planned under (`<prefix>_<NNN>.flv`, `.ts`, `.m4s`).
  final String plannedPath;

  /// Final path; differs from [plannedPath] when that name was taken (`-1`, `-2`…).
  String? finalPath;

  /// Final path once the file is created.
  String get path => finalPath ?? plannedPath;

  /// File name of [path].
  String get name => p.basename(path);

  /// Bytes written (or queued for writing) to the file.
  int bytes = 0;

  /// Media time in the file, in ms (file time starts at 0).
  int durationMs = 0;

  /// Whether the file was closed and renamed to [path].
  bool closed = false;
}

/// Segment lifecycle notifications for companions such as the chat XML.
sealed class SegmentEvent {
  const new(this.segment);

  /// The segment.
  final RecordedSegment segment;
}

/// A segment started; its first media has file time 0.
final class SegmentOpened extends SegmentEvent {
  /// Creates the event.
  const new(super.segment);
}

/// A segment was closed (its file is complete).
final class SegmentClosed extends SegmentEvent {
  /// Creates the event.
  const new(super.segment);
}

/// What a recording session writes through: the FLV writer (§6) or the HLS
/// writer (§7, §8). A session has one at a time; switching between FLV and
/// HLS lines closes one and opens the other, numbering continues.
abstract interface class SessionWriter {
  /// Units of media written: FLV tags, HLS segments.
  int get mediaTags;

  /// Bytes written (or queued) to segment files.
  int get bytesWritten;

  /// Media time written, summed over segments.
  Duration get mediaDuration;

  /// Segments so far, the open one last.
  List<RecordedSegment> get segments;

  /// Completes when the write queue is below its limit (backpressure, §6.8).
  Future<void> get ready;

  /// Completes with the fatal error that stopped writing, if one happens.
  Future<RecordFailure> get failure;

  /// The fatal error, once there is one.
  RecordFailure? get failed;

  /// File time in the current segment that corresponds to [wall] (chat
  /// timing, §17), clamped to what was written; null without a segment.
  int? fileTimeAt(DateTime wall);

  /// Completes when the output can end without a cut picture (§6.7), or after [max].
  Future<void> waitForPicture(Duration max);

  /// Marks the start of a new upstream connection after the previous one
  /// was lost at [lostAt] for [reason].
  void beginConnection({DateTime? lostAt, GapReason reason = GapReason.eof});

  /// Ends the output: drains the queue, closes and renames the open segment.
  Future<List<RecordedSegment>> close({Duration giveUpAfter = const Duration(seconds: 10)});
}
