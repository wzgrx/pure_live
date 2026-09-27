import 'dart:typed_data';

import 'package:live_record/src/remux.dart';

const _blockShift = 14;
const int _blockLength = 1 << _blockShift;
const int _blockMask = _blockLength - 1;

/// A growable list of unsigned 32-bit values in 64 KiB blocks: compact, and
/// growing never copies what is already stored.
final class U32Blocks {
  final _blocks = <Uint32List>[];
  var _length = 0;

  /// Number of values.
  int get length => _length;

  /// Whether the list is empty.
  bool get isEmpty => _length == 0;

  /// Bytes held by the blocks.
  int get capacityBytes => _blocks.length * _blockLength * 4;

  /// Appends [value] (taken modulo 2^32).
  void add(int value) {
    final index = _length & _blockMask;
    if (index == 0) _blocks.add(Uint32List(_blockLength));
    _blocks.last[index] = value;
    _length++;
  }

  /// The value at [index].
  int operator [](int index) => _blocks[index >> _blockShift][index & _blockMask];

  /// Replaces the value at [index].
  void operator []=(int index, int value) => _blocks[index >> _blockShift][index & _blockMask] = value;

  /// The last value.
  int get last => this[_length - 1];

  set last(int value) => this[_length - 1] = value;
}

/// A growable list of signed 64-bit values in 128 KiB blocks.
final class I64Blocks {
  final _blocks = <Int64List>[];
  var _length = 0;

  /// Number of values.
  int get length => _length;

  /// Appends [value].
  void add(int value) {
    final index = _length & _blockMask;
    if (index == 0) _blocks.add(Int64List(_blockLength));
    _blocks.last[index] = value;
    _length++;
  }

  /// The value at [index].
  int operator [](int index) => _blocks[index >> _blockShift][index & _blockMask];

  /// The last value.
  int get last => this[_length - 1];
}

/// Run-length encoded values (`stts`, `ctts`): consecutive equal values share an entry.
final class RunList {
  /// Run lengths.
  final counts = U32Blocks();

  /// Run values (32-bit two's complement for signed values).
  final values = U32Blocks();

  /// Number of runs.
  int get length => counts.length;

  /// Appends one [value] (a signed value is stored as its 32-bit two's complement).
  void add(int value) {
    final stored = value & 0xffffffff;
    if (counts.isEmpty || values.last != stored || counts.last == 0xffffffff) {
      counts.add(1);
      values.add(stored);
    } else {
      counts.last = counts.last + 1;
    }
  }
}

/// Sample tables of one MP4 track, built one sample at a time in decode
/// order: sizes (`stsz`), decode deltas (`stts`, run-length encoded),
/// composition offsets (`ctts`, run-length encoded), sync samples (`stss`)
/// and chunks (`stsc` runs, `stco`/`co64` offsets relative to the start of
/// the `mdat` payload). Memory is about 4 bytes per sample plus the runs.
final class TrackTable {
  /// Creates the tables of a track with [timescale] ticks per second.
  new(this.timescale);

  /// Media timescale (ticks per second).
  final int timescale;

  /// Sample sizes.
  final sizes = U32Blocks();

  /// Decode time deltas (the last one is set by [finish]).
  final stts = RunList();

  /// Composition offsets.
  final ctts = RunList();

  /// 1-based numbers of the sync samples.
  final syncSamples = U32Blocks();

  /// Chunk offsets relative to the first byte of the `mdat` payload.
  final chunkOffsets = I64Blocks();

  /// `stsc` runs: first chunk (1-based) of each run.
  final chunkRunFirst = U32Blocks();

  /// `stsc` runs: samples per chunk of each run.
  final chunkRunSamples = U32Blocks();

  /// Number of samples.
  int get sampleCount => sizes.length;

  /// Whether any composition offset is not 0 (`ctts` needed).
  bool hasCompositionOffsets = false;

  /// Whether any composition offset is negative (`ctts` version 1).
  bool hasNegativeOffsets = false;

  /// Payload bytes.
  int totalBytes = 0;

  /// Largest sample.
  int maxSampleSize = 0;

  /// Composition offset of the first sample.
  int firstOffset = 0;

  /// Largest presentation time (decode time + offset) of any sample.
  int maxPresentation = 0;

  /// Sum of the sample durations once [finish] ran.
  int duration = 0;

  /// Largest number of payload bytes decoded within one second.
  int maxBytesPerSecond = 0;

  int? _lastDts;
  final _recent = Int64List(64);
  var _recentCount = 0;
  var _second = -1;
  var _secondBytes = 0;
  var _chunkedSamples = 0;

  /// Adds a sample decoded at [dts] and presented at [dts] + [offset] (ticks).
  /// [dts] must be larger than the previous one.
  void add({required int dts, required int offset, required int size, required bool sync}) {
    final last = _lastDts;
    if (last != null) {
      final delta = dts - last;
      if (delta <= 0 || delta > 0xffffffff) throw RemuxException('bad sample duration $delta');
      stts.add(delta);
      _recent[_recentCount++ % _recent.length] = delta;
    } else {
      firstOffset = offset;
    }
    if (offset < -0x80000000 || offset > 0x7fffffff) throw RemuxException('composition offset $offset out of range');
    _lastDts = dts;
    sizes.add(size);
    ctts.add(offset);
    if (offset != 0) hasCompositionOffsets = true;
    if (offset < 0) hasNegativeOffsets = true;
    if (sync) syncSamples.add(sizes.length);
    totalBytes += size;
    if (size > maxSampleSize) maxSampleSize = size;
    if (dts + offset > maxPresentation) maxPresentation = dts + offset;
    final second = dts ~/ timescale;
    if (second != _second) {
      _second = second;
      _secondBytes = 0;
    }
    _secondBytes += size;
    if (_secondBytes > maxBytesPerSecond) maxBytesPerSecond = _secondBytes;
  }

  /// Median of the recent sample durations; [fallback] when there are none.
  int medianDuration(int fallback) {
    final count = _recentCount < _recent.length ? _recentCount : _recent.length;
    if (count == 0) return fallback;
    final sorted = Int64List.fromList(_recent.sublist(0, count))..sort();
    return sorted[count ~/ 2];
  }

  /// Ends the track: the last sample lasts [lastDuration] ticks.
  void finish(int lastDuration) {
    final last = _lastDts;
    if (last == null) return;
    final value = lastDuration > 0 ? lastDuration : 1;
    stts.add(value);
    duration = last + value;
    if (maxPresentation < last + firstOffset) maxPresentation = last + firstOffset;
  }

  /// End of the presentation: the latest presentation time plus one sample duration.
  int get presentationEnd {
    final end = maxPresentation + (stts.length == 0 ? 0 : stts.values.last);
    return end > duration ? end : duration;
  }

  /// Adds a chunk of [samples] samples starting [offset] bytes into the `mdat` payload.
  void addChunk(int offset, int samples) {
    chunkOffsets.add(offset);
    if (chunkRunSamples.isEmpty || chunkRunSamples.last != samples) {
      chunkRunFirst.add(chunkOffsets.length);
      chunkRunSamples.add(samples);
    }
    _chunkedSamples += samples;
  }

  /// Samples placed in chunks so far.
  int get chunkedSamples => _chunkedSamples;

  /// Approximate bytes held by the tables.
  int get memoryBytes =>
      sizes.capacityBytes +
      stts.counts.capacityBytes * 2 +
      ctts.counts.capacityBytes * 2 +
      syncSamples.capacityBytes +
      chunkOffsets.length * 8 +
      chunkRunFirst.capacityBytes * 2;
}

/// Maps FLV video timestamps (ms) to strictly increasing decode times in a
/// 90 kHz timescale starting at 0. Presentation times are kept: a decode
/// time pushed forward (duplicate timestamps) lowers the composition offset.
final class VideoTimeline {
  /// Ticks per second.
  static const timescale = 90000;

  static const int _perMs = timescale ~/ 1000;

  /// First decode timestamp (ms) of the track.
  int? firstMs;

  int? _last;

  /// Decode time and composition offset (ticks) of a sample at [dtsMs] + [ctsMs].
  ({int dts, int offset}) next(int dtsMs, int ctsMs) {
    final first = firstMs ??= dtsMs;
    var dts = (dtsMs - first) * _perMs;
    final pts = dts + ctsMs * _perMs;
    final last = _last;
    if (last != null && dts <= last) {
      if (last - dts > timescale) {
        throw RemuxException('video timestamps go back ${(last - dts) ~/ _perMs} ms at $dtsMs ms');
      }
      dts = last + 1;
    }
    _last = dts;
    return (dts: dts, offset: pts - dts);
  }
}

/// Maps FLV audio timestamps (ms) to decode times in samples: each frame
/// lasts [frameSamples] unless the timestamps move away from that by a frame
/// or more (a gap in the recording, or a clock drift), where the timeline
/// follows the timestamps again. FLV rounds to whole milliseconds, so
/// following the timestamps exactly would jitter every frame.
final class AudioTimeline {
  /// Creates the timeline of a track at [sampleRate].
  new({required this.sampleRate, required this.frameSamples});

  /// Samples per second (the track timescale).
  final int sampleRate;

  /// Samples per frame.
  final int frameSamples;

  /// First timestamp (ms) of the track.
  int? firstMs;

  int? _last;

  /// Decode time (samples) of a frame at [dtsMs].
  int next(int dtsMs) {
    final first = firstMs ??= dtsMs;
    final target = ((dtsMs - first) * sampleRate / 1000).round();
    final last = _last;
    if (last == null) {
      _last = 0;
      return 0;
    }
    if (last - target > sampleRate) {
      throw RemuxException('audio timestamps go back ${((last - target) * 1000 / sampleRate).round()} ms at $dtsMs ms');
    }
    final nominal = last + frameSamples;
    final dts = (target - nominal).abs() < frameSamples ? nominal : (target > last ? target : last + 1);
    _last = dts;
    return dts;
  }
}

/// Decides how samples are grouped into chunks in the `mdat`, identically
/// in both passes: a track's chunk closes when it spans [windowMs] of its own
/// timestamps or would exceed [maxChunkBytes], and a chunk of another track
/// older than twice the window closes too, so the tracks stay interleaved
/// about every [windowMs]. Chunks are emitted through `onChunk` in `mdat` order.
final class ChunkPlanner {
  /// Creates a planner for [tracks] tracks.
  new({required int tracks, required this.onChunk, this.windowMs = 500, this.maxChunkBytes = 4 << 20})
    : _count = List.filled(tracks, 0),
      _bytes = List.filled(tracks, 0),
      _first = List.filled(tracks, 0);

  /// Receives each closed chunk: track index, sample count, bytes.
  final void Function(int track, int samples, int bytes) onChunk;

  /// Media time one chunk spans at most.
  final int windowMs;

  /// Bytes one chunk holds at most (a larger sample gets a chunk of its own).
  final int maxChunkBytes;

  final List<int> _count;
  final List<int> _bytes;
  final List<int> _first;

  /// Payload bytes waiting in open chunks.
  int get pendingBytes => _bytes.fold(0, (sum, value) => sum + value);

  /// Adds a sample of [track] with timestamp [ms] and [size] bytes.
  void add(int track, int ms, int size) {
    for (var other = 0; other < _count.length; other++) {
      if (_count[other] == 0) continue;
      final age = ms - _first[other];
      final close = other == track ? age >= windowMs || _bytes[other] + size > maxChunkBytes : age >= 2 * windowMs;
      if (close) _close(other);
    }
    if (_count[track] == 0) _first[track] = ms;
    _count[track]++;
    _bytes[track] += size;
  }

  /// Closes every open chunk, in track order.
  void finish() {
    for (var track = 0; track < _count.length; track++) {
      if (_count[track] > 0) _close(track);
    }
  }

  void _close(int track) {
    final samples = _count[track];
    final bytes = _bytes[track];
    _count[track] = 0;
    _bytes[track] = 0;
    onChunk(track, samples, bytes);
  }
}
