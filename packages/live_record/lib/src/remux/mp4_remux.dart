import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/remux.dart';
import 'package:live_record/src/remux/codec_config.dart';
import 'package:live_record/src/remux/mp4_writer.dart';
import 'package:live_record/src/remux/sample_table.dart';

/// Index of the video track in [Mp4Sample.track].
const videoTrack = 0;

/// Index of the audio track in [Mp4Sample.track].
const audioTrack = 1;

/// Seconds between 1904-01-01 (MP4 epoch) and 1970-01-01.
const _mp4Epoch = 2082844800;

/// One sample of a demuxed input, as the MP4 writer places it.
final class Mp4Sample {
  /// Creates a sample.
  const new({
    required this.track,
    required this.ms,
    required this.dts,
    required this.offset,
    required this.sync,
    required this.data,
  });

  /// [videoTrack] or [audioTrack].
  final int track;

  /// Decode time in milliseconds on a timeline shared by the tracks: it
  /// decides the interleaving of chunks.
  final int ms;

  /// Decode time in the track's timescale, from 0, strictly increasing.
  final int dts;

  /// Composition offset in the track's timescale.
  final int offset;

  /// Whether the sample is a sync sample.
  final bool sync;

  /// The sample payload as the MP4 stores it.
  final Uint8List data;
}

/// One demultiplexer run over a whole input for [remuxToMp4]. Each pass of
/// the remux uses a fresh source; both must produce the same samples.
abstract interface class Mp4Source {
  /// Reads the input from [reader] and hands every sample to [onSample] in
  /// file order. [onBlock] gets the input bytes read so far; [afterBlock]
  /// runs after each block (the copy pass writes then). Throws
  /// [RemuxException] for anything it cannot copy faithfully.
  Future<void> read(
    RecordReader reader, {
    required int blockSize,
    required void Function(Mp4Sample sample) onSample,
    required void Function(int read) onBlock,
    bool Function()? isCancelled,
    Future<void> Function()? afterBlock,
  });

  /// Timescale of [track]; asked when its first sample arrives.
  int timescale(int track);

  /// Duration of a track's last sample when nothing better is known (ticks).
  int fallbackDuration(int track);

  /// The track descriptions after the first pass, for the tracks in [tables]
  /// (by track index) that have samples.
  List<Mp4Track> tracks(Map<int, TrackTable> tables);

  /// Samples dropped on purpose (before the first configuration or keyframe).
  int get dropped;
}

/// What a remux produced.
final class RemuxResult {
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

  /// Video codec, or null without video (or one the recorder does not know).
  final VideoCodec? videoCodec;

  /// Audio sampling rate (the track timescale), or null without audio.
  final int? audioSampleRate;

  /// Movie duration.
  final Duration duration;

  /// Size of the input.
  final int inputBytes;

  /// Size of the MP4.
  final int outputBytes;

  /// Size of the `moov` box.
  final int moovBytes;

  /// Whether chunk offsets needed 64 bits.
  final bool co64;

  /// Units dropped on purpose (before the first configuration or keyframe).
  final int droppedTags;

  /// Memory the sample tables held (bytes).
  final int tableBytes;
}

/// Copies the samples [source] demuxes from [input] into a faststart MP4 at
/// [output] (created exclusively), without decoding, in two passes like the
/// FLV remuxer (ADR 0021): the first builds compact sample tables and the
/// chunk plan, the header is laid out from them, the second demuxes again
/// and writes the payloads in the planned order, holding about half a
/// second of media per track. [onProgress] gets input bytes (each pass
/// counts half); [isCancelled] is checked between blocks and samples. Any
/// failure throws [RemuxException] and removes [output].
Future<RemuxResult> remuxToMp4({
  required Mp4Source Function() source,
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
    final plan = await _plan(source(), reader, blockSize, isCancelled, (read) => onProgress?.call(read ~/ 2));
    final header = Mp4Header(
      tracks: plan.tracks,
      payloadBytes: plan.payloadBytes,
      creationTime: clock.now().toUtc().millisecondsSinceEpoch ~/ 1000 + _mp4Epoch,
    );
    sink = await files.create(output);
    final out = Mp4Output(sink);
    await header.write(out);
    if (out.length != header.payloadStart) throw StateError('header size ${out.length} != ${header.payloadStart}');
    await _copy(
      source(),
      reader,
      blockSize,
      isCancelled,
      plan,
      header,
      out,
      (read) => onProgress?.call((length + read) ~/ 2),
    );
    await out.flush();
    if (out.length != header.payloadStart + header.payloadBytes) {
      throw RemuxException('wrote ${out.length} bytes, planned ${header.payloadStart + header.payloadBytes}');
    }
    await sink.flush();
    // A failing close may mean lost data: it fails the remux.
    closed = true;
    await sink.close();
    done = true;
    final video = plan.tables[videoTrack];
    final audio = plan.tables[audioTrack];
    return RemuxResult(
      videoSamples: video?.sampleCount ?? 0,
      audioSamples: audio?.sampleCount ?? 0,
      keyframes: video?.syncSamples.length ?? 0,
      videoCodec: switch (plan.tracks.where((track) => track.isVideo).firstOrNull?.codec.entryType) {
        'avc1' || 'avc3' => VideoCodec.avc,
        'hvc1' || 'hev1' => VideoCodec.hevc,
        _ => null,
      },
      audioSampleRate: audio?.timescale,
      duration: Duration(milliseconds: header.durationMs),
      inputBytes: length,
      outputBytes: out.length,
      moovBytes: header.moovSize,
      co64: header.co64,
      droppedTags: plan.dropped,
      tableBytes: plan.tables.values.fold(0, (sum, table) => sum + table.memoryBytes),
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
  new({required this.tables, required this.tracks, required this.payloadBytes, required this.dropped});

  final Map<int, TrackTable> tables;
  final List<Mp4Track> tracks;
  final int payloadBytes;
  final int dropped;
}

Future<_Plan> _plan(
  Mp4Source source,
  RecordReader reader,
  int blockSize,
  bool Function()? isCancelled,
  void Function(int) progress,
) async {
  final tables = <int, TrackTable>{};
  var payload = 0;
  final planner = ChunkPlanner(
    tracks: 2,
    onChunk: (track, samples, bytes) {
      tables[track]!.addChunk(payload, samples);
      payload += bytes;
    },
  );
  await source.read(
    reader,
    blockSize: blockSize,
    isCancelled: isCancelled,
    onBlock: progress,
    onSample: (sample) {
      (tables[sample.track] ??= TrackTable(
        source.timescale(sample.track),
      )).add(dts: sample.dts, offset: sample.offset, size: sample.data.length, sync: sample.sync);
      planner.add(sample.track, sample.ms, sample.data.length);
    },
  );
  planner.finish();
  for (final MapEntry(key: track, value: table) in tables.entries) {
    table.finish(table.medianDuration(source.fallbackDuration(track)));
  }
  final tracks = source.tracks(tables);
  if (tracks.isEmpty) throw const RemuxException('no audio or video samples');
  return _Plan(tables: tables, tracks: tracks, payloadBytes: payload, dropped: source.dropped);
}

Future<void> _copy(
  Mp4Source source,
  RecordReader reader,
  int blockSize,
  bool Function()? isCancelled,
  _Plan plan,
  Mp4Header header,
  Mp4Output out,
  void Function(int) progress,
) async {
  final pending = [<Uint8List>[], <Uint8List>[]];
  final ready = <List<Uint8List>>[];
  final nextSample = [0, 0];
  final nextChunk = [0, 0];
  var planned = 0;
  final planner = ChunkPlanner(
    tracks: 2,
    onChunk: (track, samples, bytes) {
      final table = plan.tables[track]!;
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

  await source.read(
    reader,
    blockSize: blockSize,
    isCancelled: isCancelled,
    onBlock: progress,
    afterBlock: drain,
    onSample: (sample) {
      final table = plan.tables[sample.track];
      final index = nextSample[sample.track]++;
      if (table == null || index >= table.sampleCount || table.sizes[index] != sample.data.length) {
        throw const RemuxException('input changed during remux (samples)');
      }
      planner.add(sample.track, sample.ms, sample.data.length);
      pending[sample.track].add(sample.data);
    },
  );
  planner.finish();
  await drain();
  for (final MapEntry(key: track, value: table) in plan.tables.entries) {
    if (nextSample[track] != table.sampleCount) throw const RemuxException('input changed during remux (sample count)');
  }
  if (planned != header.payloadBytes) throw const RemuxException('input changed during remux (size)');
}

/// Joins the timestamps of a recording made of several stretches (HLS
/// discontinuities, a restarted stream, a new CDN) into one timeline for the
/// MP4 (spec §10): a track's timestamp that moves back more than [back] or
/// forward more than [window] starts a new stretch, placed right after
/// everything written so far; the other tracks join that stretch when their
/// own timestamps jump to it. Smaller forward steps keep the timeline, so a
/// missed segment stays a hole in the file time, like the FLV writer (§6.3).
/// Units are the input's ticks (90 kHz for MPEG-TS).
final class TimelineJoiner {
  /// Creates a joiner for [tracks] tracks.
  new({required this.window, required this.back, int tracks = 2})
    : _last = List<int?>.filled(tracks, null),
      _offset = List<int>.filled(tracks, 0),
      _end = List<int?>.filled(tracks, null),
      _epochOf = List<int>.filled(tracks, 0);

  /// Largest forward step inside a stretch.
  final int window;

  /// Largest backward step inside a stretch.
  final int back;

  final List<int?> _last;
  final List<int> _offset;
  final List<int?> _end;
  final List<int> _epochOf;
  int? _epochRaw;
  int _epochOffset = 0;
  int _epoch = 0;

  /// Stretches started after the first.
  int joins = 0;

  /// The joined time of [raw] on [track]; [duration] is how long the unit
  /// lasts (for placing a following stretch).
  int adjust(int track, int raw, {required int duration}) {
    final last = _last[track];
    final epochRaw = _epochRaw;
    if (epochRaw == null) {
      _epochRaw = raw;
      _epochOffset = 0;
      _join(track);
    } else if (last == null) {
      // A track's first unit: in the current stretch when close to it.
      if ((raw - epochRaw).abs() > window) _newEpoch(raw);
      _join(track);
    } else {
      final step = raw - last;
      if (step < -back || step > window) {
        // Another track may have started the stretch this one jumps to.
        final joinable = _epochOf[track] < _epoch && (raw - epochRaw).abs() <= window;
        if (!joinable) _newEpoch(raw);
        _join(track);
      }
    }
    _last[track] = raw;
    final adjusted = raw + _offset[track];
    final end = adjusted + duration;
    if (_end[track] == null || end > _end[track]!) _end[track] = end;
    return adjusted;
  }

  void _join(int track) {
    _epochOf[track] = _epoch;
    _offset[track] = _epochOffset;
  }

  void _newEpoch(int raw) {
    var end = 0;
    for (final value in _end) {
      if (value != null && value > end) end = value;
    }
    _epoch++;
    joins++;
    _epochRaw = raw;
    _epochOffset = end - raw;
  }
}
