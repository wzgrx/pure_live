import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/remux.dart';
import 'package:live_record/src/remux/codec_config.dart';
import 'package:live_record/src/remux/flv_demux.dart';
import 'package:live_record/src/remux/mp4_writer.dart';
import 'package:live_record/src/remux/sample_table.dart';
import 'package:meta/meta.dart';

/// What [remuxFlvToMp4] produced.
@immutable
final class FlvRemuxResult {
  /// Creates a result.
  const new({
    required this.videoSamples,
    required this.audioSamples,
    required this.keyframes,
    required this.videoCodec,
    required this.audioSampleRate,
    required this.duration,
    required this.inputBytes,
    required this.outputBytes,
    required this.moovBytes,
    required this.co64,
    required this.droppedTags,
    required this.tableBytes,
  });

  /// Video samples written.
  final int videoSamples;

  /// Audio samples written.
  final int audioSamples;

  /// Video sync samples.
  final int keyframes;

  /// Video codec, or null without video.
  final VideoCodec? videoCodec;

  /// Audio sampling rate, or null without audio.
  final int? audioSampleRate;

  /// Movie duration.
  final Duration duration;

  /// Size of the FLV.
  final int inputBytes;

  /// Size of the MP4.
  final int outputBytes;

  /// Size of the `moov` box.
  final int moovBytes;

  /// Whether chunk offsets needed 64 bits.
  final bool co64;

  /// Media tags dropped because no sequence header preceded them.
  final int droppedTags;

  /// Memory the sample tables held (bytes).
  final int tableBytes;
}

/// [Remuxer] that converts FLV recordings to faststart MP4 in pure Dart
/// ([remuxFlvToMp4]): same code on Android and Windows, no FFmpeg.
final class FlvToMp4Remuxer implements Remuxer {
  /// Creates the remuxer over [files] (the local file system by default).
  const new({this.files = const IoRecordFiles()});

  /// File access.
  final RecordFiles files;

  @override
  Future<void> remux(RemuxJob job) async {
    var cancelled = false;
    unawaited(job.cancelled.then((_) => cancelled = true));
    await remuxFlvToMp4(
      files: files,
      input: job.input,
      output: job.output,
      onProgress: job.onProgress,
      isCancelled: () => cancelled,
    );
  }
}

const _video = 0;
const _audio = 1;

/// Seconds between 1904-01-01 (MP4 epoch) and 1970-01-01.
const _mp4Epoch = 2082844800;

/// Copies the H.264/H.265 and AAC streams of the FLV at [input] into a
/// faststart MP4 at [output] (created exclusively), without decoding.
///
/// Two passes over the input keep memory bounded: the first demuxes every
/// tag and builds compact sample tables (about 4 bytes per sample); the
/// header (`ftyp`, `moov`) is laid out from them; the second demuxes again
/// and writes the payloads into `mdat` in the planned chunk order, holding at
/// most about half a second of media per track. [onProgress] gets input
/// bytes (the two passes count half each); [isCancelled] is checked between
/// tags. Any malformed or unsupported input throws [RemuxException] and
/// removes [output].
Future<FlvRemuxResult> remuxFlvToMp4({
  required String input,
  required String output,
  RecordFiles files = const IoRecordFiles(),
  void Function(int bytesRead)? onProgress,
  bool Function()? isCancelled,
  int blockSize = 1 << 20,
}) async {
  RecordReader? reader;
  RecordSink? sink;
  var done = false;
  var closed = false;
  try {
    reader = await files.open(input);
    final length = reader.length;
    final plan = await _plan(reader, blockSize, isCancelled, (read) => onProgress?.call(read ~/ 2));
    final header = Mp4Header(
      tracks: plan.tracks,
      payloadBytes: plan.payloadBytes,
      creationTime: clock.now().toUtc().millisecondsSinceEpoch ~/ 1000 + _mp4Epoch,
    );
    sink = await files.create(output);
    final out = Mp4Output(sink);
    await header.write(out);
    if (out.length != header.payloadStart) throw StateError('header size ${out.length} != ${header.payloadStart}');
    await _copy(reader, blockSize, isCancelled, plan, header, out, (read) => onProgress?.call((length + read) ~/ 2));
    await out.flush();
    if (out.length != header.payloadStart + header.payloadBytes) {
      throw RemuxException('wrote ${out.length} bytes, planned ${header.payloadStart + header.payloadBytes}');
    }
    await sink.flush();
    // A failing close may mean lost data: it fails the remux.
    closed = true;
    await sink.close();
    done = true;
    final video = plan.video;
    final audio = plan.audio;
    return FlvRemuxResult(
      videoSamples: video.sampleCount,
      audioSamples: audio?.sampleCount ?? 0,
      keyframes: video.syncSamples.length,
      videoCodec: video.sampleCount > 0 ? plan.videoConfig?.codec : null,
      audioSampleRate: audio?.timescale,
      duration: Duration(milliseconds: header.durationMs),
      inputBytes: length,
      outputBytes: out.length,
      moovBytes: header.moovSize,
      co64: header.co64,
      droppedTags: plan.dropped,
      tableBytes: video.memoryBytes + (audio?.memoryBytes ?? 0),
    );
  } on RemuxException {
    rethrow;
  } on Object catch (error) {
    throw RemuxException('$error');
  } finally {
    try {
      await reader?.close();
      if (!closed) await sink?.close();
    } on Object {
      // Already failing, or only the input failed to close.
    }
    if (!done && sink != null) {
      try {
        await files.delete(output);
      } on Object {
        // Left for the caller, which deletes the partial file too.
      }
    }
  }
}

final class _Plan {
  new({
    required this.video,
    required this.audio,
    required this.tracks,
    required this.payloadBytes,
    required this.videoConfig,
    required this.dropped,
  });

  final TrackTable video;
  final TrackTable? audio;
  final List<Mp4Track> tracks;
  final int payloadBytes;
  final VideoConfig? videoConfig;
  final int dropped;

  TrackTable? table(int track) => track == _video ? video : audio;
}

/// Reads [reader] block by block and hands every tag (not the file header) to [onTag].
Future<void> _readTags(
  RecordReader reader,
  int blockSize,
  bool Function()? isCancelled,
  void Function(int read) onBlock,
  void Function(Uint8List tag, int offset) onTag, {
  Future<void> Function()? afterBlock,
}) async {
  final framer = FlvFramer();
  final length = reader.length;
  var read = 0;
  var offset = 0;
  var header = true;
  while (read < length) {
    if (isCancelled?.call() ?? false) throw const RemuxException('cancelled');
    final wanted = length - read < blockSize ? length - read : blockSize;
    final block = await reader.read(read, wanted);
    if (block.isEmpty) throw RemuxException('input ended at $read of $length bytes');
    read += block.length;
    final List<Uint8List> packets;
    try {
      packets = framer.add(block);
    } on FormatException catch (error) {
      throw RemuxException('${error.message} at offset ${offset + framer.pending}');
    }
    for (final packet in packets) {
      if (header) {
        header = false;
      } else {
        if (isCancelled?.call() ?? false) throw const RemuxException('cancelled');
        onTag(packet, offset);
      }
      offset += packet.length;
    }
    await afterBlock?.call();
    onBlock(read);
  }
  if (header) throw const RemuxException('not an FLV file');
  if (framer.pending > 0) throw RemuxException('truncated tag at offset $offset (${framer.pending} bytes)');
}

/// First pass: demux everything, build the sample tables and the chunk plan.
Future<_Plan> _plan(
  RecordReader reader,
  int blockSize,
  bool Function()? isCancelled,
  void Function(int) progress,
) async {
  final demuxer = FlvDemuxer();
  final video = TrackTable(VideoTimeline.timescale);
  final videoTime = VideoTimeline();
  TrackTable? audio;
  AudioTimeline? audioTime;
  var payload = 0;
  final planner = ChunkPlanner(
    tracks: 2,
    onChunk: (track, samples, bytes) {
      (track == _video ? video : audio!).addChunk(payload, samples);
      payload += bytes;
    },
  );
  await _readTags(reader, blockSize, isCancelled, progress, (tag, offset) {
    final sample = demuxer.add(tag, offset);
    if (sample == null) return;
    final size = sample.data.length;
    if (sample.video) {
      final time = videoTime.next(sample.dtsMs, sample.ctsMs);
      video.add(dts: time.dts, offset: time.offset, size: size, sync: sample.keyframe);
      planner.add(_video, sample.dtsMs, size);
    } else {
      final config = demuxer.audio!;
      final table = audio ??= TrackTable(config.sampleRate);
      final timeline = audioTime ??= AudioTimeline(sampleRate: config.sampleRate, frameSamples: config.frameSamples);
      table.add(dts: timeline.next(sample.dtsMs), offset: 0, size: size, sync: true);
      planner.add(_audio, sample.dtsMs, size);
    }
  });
  planner.finish();
  if (demuxer.video == null && demuxer.videoWithoutConfig > 0) {
    throw const RemuxException('video tags without a sequence header');
  }
  if (demuxer.audio == null && demuxer.audioWithoutConfig > 0) {
    throw const RemuxException('AAC tags without an AudioSpecificConfig');
  }
  video.finish(video.medianDuration(VideoTimeline.timescale ~/ 30));
  final audioConfig = demuxer.audio;
  final audioTable = audio;
  if (audioTable != null && audioConfig != null) audioTable.finish(audioTable.medianDuration(audioConfig.frameSamples));
  final metadata = demuxer.metadata;
  int dimension(String key) => switch (metadata[key]) {
    final num value when value > 0 && value < 65536 => value.round(),
    _ => 0,
  };
  final videoConfig = demuxer.video;
  final tracks = [
    if (video.sampleCount > 0 && videoConfig != null)
      Mp4Track(
        table: video,
        codec: Mp4VideoCodec(videoConfig),
        startMs: videoTime.firstMs!,
        fallbackWidth: dimension('width'),
        fallbackHeight: dimension('height'),
      ),
    if (audioTable != null && audioTable.sampleCount > 0 && audioConfig != null)
      Mp4Track(table: audioTable, codec: Mp4AacCodec(audioConfig), startMs: audioTime!.firstMs!),
  ];
  if (tracks.isEmpty) throw const RemuxException('no audio or video samples');
  return _Plan(
    video: video,
    audio: audioTable,
    tracks: tracks,
    payloadBytes: payload,
    videoConfig: videoConfig,
    dropped: demuxer.videoWithoutConfig + demuxer.audioWithoutConfig,
  );
}

/// Second pass: demux again and write the payloads chunk by chunk as planned.
Future<void> _copy(
  RecordReader reader,
  int blockSize,
  bool Function()? isCancelled,
  _Plan plan,
  Mp4Header header,
  Mp4Output out,
  void Function(int) progress,
) async {
  final demuxer = FlvDemuxer();
  final pending = [<Uint8List>[], <Uint8List>[]];
  final ready = <List<Uint8List>>[];
  final nextSample = [0, 0];
  final nextChunk = [0, 0];
  var planned = 0;
  final planner = ChunkPlanner(
    tracks: 2,
    onChunk: (track, samples, bytes) {
      final table = plan.table(track)!;
      final chunk = nextChunk[track]++;
      if (chunk >= table.chunkOffsets.length || table.chunkOffsets[chunk] != planned) {
        throw const RemuxException('input changed during remux (chunk layout)');
      }
      final data = pending[track];
      if (data.length != samples) throw const RemuxException('input changed during remux (chunk samples)');
      pending[track] = [];
      ready.add(data);
      planned += bytes;
    },
  );
  Future<void> drain() async {
    for (final chunk in ready) {
      for (final data in chunk) {
        await out.add(data);
      }
    }
    ready.clear();
  }

  await _readTags(reader, blockSize, isCancelled, progress, (tag, offset) {
    final sample = demuxer.add(tag, offset);
    if (sample == null) return;
    final track = sample.video ? _video : _audio;
    final table = plan.table(track);
    final index = nextSample[track]++;
    if (table == null || index >= table.sampleCount || table.sizes[index] != sample.data.length) {
      throw const RemuxException('input changed during remux (samples)');
    }
    planner.add(track, sample.dtsMs, sample.data.length);
    pending[track].add(sample.data);
  }, afterBlock: drain);
  planner.finish();
  await drain();
  if (nextSample[_video] != plan.video.sampleCount || nextSample[_audio] != (plan.audio?.sampleCount ?? 0)) {
    throw const RemuxException('input changed during remux (sample count)');
  }
  if (planned != header.payloadBytes) throw const RemuxException('input changed during remux (size)');
}
