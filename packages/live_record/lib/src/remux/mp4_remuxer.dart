import 'dart:async';
import 'dart:typed_data';

import 'package:live_record/src/files.dart';
import 'package:live_record/src/remux.dart';
import 'package:live_record/src/remux/flv_to_mp4.dart';
import 'package:live_record/src/remux/fmp4_to_mp4.dart';
import 'package:live_record/src/remux/mp4_remux.dart';
import 'package:live_record/src/remux/ts_demux.dart';
import 'package:live_record/src/remux/ts_to_mp4.dart';

/// Formats the recorder writes.
enum RecordingFormat {
  /// FLV segments (`.flv`, §6).
  flv,

  /// MPEG-TS from HLS (`.ts`, §8).
  ts,

  /// Fragmented MP4 from HLS (`.m4s`: initialisation section + fragments).
  fmp4,
}

/// The format of a recording from its first bytes, or null when unknown.
RecordingFormat? recordingFormatOf(Uint8List head) {
  if (head.length >= 3 && head[0] == 0x46 && head[1] == 0x4C && head[2] == 0x56) return RecordingFormat.flv;
  if (looksLikeTs(head)) return RecordingFormat.ts;
  if (head.length >= 8) {
    final type = String.fromCharCodes(head, 4, 8);
    if (const {'ftyp', 'styp', 'moov', 'moof', 'sidx', 'prft', 'emsg'}.contains(type)) return RecordingFormat.fmp4;
  }
  return null;
}

/// Remuxes the recording at [input] to a faststart MP4 at [output] by its
/// format (spec §10): FLV ([remuxFlvToMp4]), MPEG-TS ([remuxTsToMp4]) or
/// fragmented MP4 ([remuxFmp4ToMp4]).
Future<RemuxResult> remuxRecording({
  required String input,
  required String output,
  RecordFiles files = const IoRecordFiles(),
  void Function(int bytesRead)? onProgress,
  bool Function()? isCancelled,
}) async {
  final Uint8List head;
  try {
    final reader = await files.open(input);
    try {
      head = await reader.read(0, 4 * tsPacketSize);
    } finally {
      await reader.close();
    }
  } on Object catch (error) {
    throw RemuxException('$error');
  }
  return await switch (recordingFormatOf(head)) {
    RecordingFormat.flv => remuxFlvToMp4(
      input: input,
      output: output,
      files: files,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
    RecordingFormat.ts => remuxTsToMp4(
      input: input,
      output: output,
      files: files,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
    RecordingFormat.fmp4 => remuxFmp4ToMp4(
      input: input,
      output: output,
      files: files,
      onProgress: onProgress,
      isCancelled: isCancelled,
    ),
    null => throw const RemuxException('not an FLV, MPEG-TS or fragmented MP4 recording'),
  };
}

/// [Remuxer] for every format the recorder writes (FLV, MPEG-TS, fragmented
/// MP4), in pure Dart: the same code on Android and Windows, no FFmpeg
/// (ADR 0021). The app runs it in a background isolate with
/// `IsolateRemuxer(Mp4Remuxer())`.
final class Mp4Remuxer implements Remuxer {
  /// Creates the remuxer over [files] (the local file system by default).
  const new({this.files = const IoRecordFiles()});

  /// File access.
  final RecordFiles files;

  @override
  Future<void> remux(RemuxJob job) async {
    var cancelled = false;
    unawaited(job.cancelled.then((_) => cancelled = true));
    await remuxRecording(
      files: files,
      input: job.input,
      output: job.output,
      onProgress: job.onProgress,
      isCancelled: () => cancelled,
    );
  }
}
