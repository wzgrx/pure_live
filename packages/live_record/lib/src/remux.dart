import 'dart:async';

import 'package:live_record/src/errors.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/naming.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// One remux: copy the streams of [input] into an MP4 at [output].
@immutable
final class RemuxJob {
  /// Creates a job.
  const new({
    required this.input,
    required this.output,
    required this.inputBytes,
    required this.onProgress,
    required this.cancelled,
  });

  /// Recorded file (FLV segment).
  final String input;

  /// Where to write the MP4: a `.partial` path the recorder commits afterwards.
  final String output;

  /// Size of [input].
  final int inputBytes;

  /// Reports input bytes read so far; also feeds the 60 s no-progress watchdog.
  final void Function(int bytesRead) onProgress;

  /// Completes when the job must stop (user cancel or watchdog).
  final Future<void> cancelled;
}

/// Thrown by a [Remuxer] for any demux or mux error.
final class RemuxException implements Exception {
  /// Creates the exception.
  const new(this.message, {this.unsupportedCodec = false});

  /// What failed.
  final String message;

  /// The recording is fine but uses a codec the MP4 remux does not copy
  /// (MPEG-2 video, MP2, AC-3 on IPTV): the source is kept as the result
  /// instead of failing the task (spec §10).
  final bool unsupportedCodec;

  @override
  String toString() => 'RemuxException($message)';
}

/// Converts a recorded file to MP4 by stream copy (spec §10, ADR 0021).
///
/// The implementation is the pure-Dart `FlvToMp4Remuxer` (no FFmpeg; the
/// same code on Android and Windows); the app wraps it in `IsolateRemuxer`
/// to keep the work off the UI isolate. `tools/live_cli` can also run the
/// `ffmpeg` executable for comparison.
///
/// Contract: write [RemuxJob.output] (`-c copy`, `+faststart`, no decoding),
/// throw [RemuxException] on any demux or mux error including invalid data,
/// PES size mismatches and trailer failures — an exit code of 0 does not
/// prove the input was complete (REG-RECORD-008) — report input bytes read,
/// and return soon after [RemuxJob.cancelled] completes.
abstract interface class Remuxer {
  /// Runs [job].
  Future<void> remux(RemuxJob job);
}

/// The outcome of [remuxFiles].
@immutable
final class RemuxOutcome {
  /// Creates an outcome.
  const new({required this.outputs, required this.kept, this.failure, this.skipped = const []});

  /// Committed MP4 files.
  final List<String> outputs;

  /// Sources that stay on disk (failed, skipped, or kept by
  /// `record.keepSourceAfterRemux`).
  final List<String> kept;

  /// Sources left as they are because their codec cannot go into MP4
  /// ([RemuxException.unsupportedCodec]); not a failure.
  final List<String> skipped;

  /// The first failure; null when every file converted.
  final RecordFailure? failure;
}

/// Remuxes [inputs] one after another (spec §10): each into
/// `<name>.mp4.partial`, committed by rename to a free `<name>.mp4` when the
/// remuxer succeeded and wrote more than 0 bytes. A failure deletes the
/// partial file and keeps the source; the other inputs still run. Sources are
/// deleted after success unless [keepSource]. Progress is input bytes over all
/// inputs, never decreasing, at most 0.99 until the last commit. A job without
/// progress for [watchdog] fails; [cancel] stops the current job and skips
/// the rest (sources kept).
Future<RemuxOutcome> remuxFiles({
  required RecordFiles files,
  required Remuxer remuxer,
  required List<String> inputs,
  bool keepSource = false,
  Duration watchdog = const Duration(seconds: 60),
  void Function(double progress)? onProgress,
  Future<void>? cancel,
}) async {
  final sizes = <String, int>{};
  for (final input in inputs) {
    final length = await files.length(input);
    if (length != null) sizes[input] = length;
  }
  final total = sizes.values.fold(0, (sum, size) => sum + size);
  var done = 0;
  var reported = 0.0;
  void report(int bytes) {
    if (total <= 0) return;
    final value = ((done + bytes) / total).clamp(0.0, 0.99);
    if (value <= reported) return;
    reported = value;
    onProgress?.call(value);
  }

  var cancelled = false;
  unawaited(cancel?.then((_) => cancelled = true));
  final outputs = <String>[];
  final kept = <String>[];
  final skipped = <String>[];
  RecordFailure? failure;
  for (final input in inputs) {
    final size = sizes[input];
    if (size == null) continue;
    if (cancelled) {
      kept.add(input);
      continue;
    }
    final target = await uniquePath(files, p.setExtension(input, '.mp4'));
    final partial = '$target$partialSuffix';
    final stop = Completer<void>();
    Timer? dog;
    String? stopReason;
    void arm() {
      dog?.cancel();
      dog = Timer(watchdog, () {
        stopReason = 'no progress for ${watchdog.inSeconds} s';
        if (!stop.isCompleted) stop.complete();
      });
    }

    unawaited(
      cancel?.then((_) {
        stopReason ??= 'cancelled';
        if (!stop.isCompleted) stop.complete();
      }),
    );
    arm();
    try {
      final run = remuxer.remux(
        RemuxJob(
          input: input,
          output: partial,
          inputBytes: size,
          onProgress: (bytes) {
            arm();
            report(bytes);
          },
          cancelled: stop.future,
        ),
      );
      final settled = run.then<Object?>((_) => null, onError: (Object error) => error);
      // A remuxer that ignores cancellation is abandoned after 10 s.
      final error = await Future.any([
        settled,
        stop.future.then(
          (_) => settled.timeout(const Duration(seconds: 10), onTimeout: () => const RemuxException('did not stop')),
        ),
      ]);
      dog?.cancel();
      if (error != null) throw error is RemuxException ? error : RemuxException('$error');
      if (stopReason != null) throw RemuxException(stopReason!);
      final length = await files.length(partial);
      if (length == null || length <= 0) throw const RemuxException('empty output');
      await files.rename(partial, target);
      outputs.add(target);
      if (keepSource) {
        kept.add(input);
      } else {
        try {
          await files.delete(input);
        } on Object {
          // In use: a later cleanup removes it; the remux still succeeded.
        }
      }
    } on Object catch (error) {
      dog?.cancel();
      try {
        await files.delete(partial);
      } on Object {
        // Nothing to clean up.
      }
      kept.add(input);
      if (error is RemuxException && error.unsupportedCodec) {
        skipped.add(input);
      } else {
        failure ??= RecordFailure(RecordErrorKind.remuxFailed, RecordStage.remux, '${p.basename(input)}: $error');
      }
    }
    done += size;
    report(0);
  }
  if (failure == null && !cancelled) onProgress?.call(1);
  return RemuxOutcome(outputs: outputs, kept: kept, failure: failure, skipped: skipped);
}
