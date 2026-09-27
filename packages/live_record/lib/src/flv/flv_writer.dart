import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/src/errors.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/flv/flv_codec.dart';
import 'package:live_record/src/gaps.dart';
import 'package:live_record/src/naming.dart';
import 'package:path/path.dart' as p;

/// Limits of the FLV writer (spec §6.8). Defaults follow the spec.
final class FlvWriterLimits {
  /// Creates the limits.
  const new({
    this.queueBytes = 8 * 1024 * 1024,
    this.flushInterval = const Duration(seconds: 1),
    this.flushBytes = 1024 * 1024,
    this.stallTimeout = const Duration(seconds: 30),
    this.alignmentWindow = const Duration(seconds: 60),
    this.audioOnlyAfter = 200,
  });

  /// Queued bytes above which [FlvSessionWriter.ready] makes the reader wait.
  final int queueBytes;

  /// Longest time between flushes while data arrives.
  final Duration flushInterval;

  /// Unflushed bytes that trigger a flush.
  final int flushBytes;

  /// A write or flush slower than this is a fatal disk stall.
  final Duration stallTimeout;

  /// A new connection whose first timestamp lies ahead of the written position
  /// by at most this much keeps its timeline (spec §6.3).
  final Duration alignmentWindow;

  /// Audio tags without any video tag after which a stream announcing video
  /// is recorded as audio only.
  final int audioOnlyAfter;
}

/// One output file of a session.
final class RecordedSegment {
  new _(this.index, this.plannedPath);

  /// 1-based segment number.
  final int index;

  /// Path the segment was planned under (`<prefix>_<NNN>.flv`).
  final String plannedPath;

  /// Final path; differs from [plannedPath] when that name was taken (`-1`, `-2`…).
  String? _path;

  /// Final path once the file is created.
  String get path => _path ?? plannedPath;

  /// File name of [path].
  String get name => p.basename(path);

  /// Bytes written (or queued for writing) to the file.
  int bytes = 0;

  /// Largest media timestamp in the file, in ms (file time starts at 0).
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

/// A segment started; its first media tag has file time 0.
final class SegmentOpened extends SegmentEvent {
  /// Creates the event.
  const new(super.segment);
}

/// A segment was closed (its file is complete).
final class SegmentClosed extends SegmentEvent {
  /// Creates the event.
  const new(super.segment);
}

sealed class _Op {
  const new();
}

final class _Open extends _Op {
  const new(this.segment);
  final RecordedSegment segment;
}

final class _Write extends _Op {
  const new(this.bytes);
  final Uint8List bytes;
}

final class _Flush extends _Op {
  const new();
}

final class _Close extends _Op {
  const new(this.segment);
  final RecordedSegment segment;
}

final class _Barrier extends _Op {
  new();
  final done = Completer<void>();
}

final class _Held {
  new(this.bytes, {required this.video, required this.fileTs});
  final Uint8List bytes;
  final bool video;
  final int fileTs;
}

/// Writes one recording session as FLV segments (spec §6).
///
/// Packets come from `FlvFramer` or `FlvSplicer`: a file header, then tags.
/// Each segment starts with the header (flags of the session's first
/// connection), the first connection's script tag, the video and audio
/// configurations and a keyframe at file time 0. Timestamps are monotonic
/// per stream; a new connection ([beginConnection]) keeps its timeline when
/// it continues the written one within 60 s, and is otherwise rebased to the
/// written end plus one frame, with the gap recorded in `gaps.json`. A
/// configuration change or a time/size limit opens the next segment at a
/// keyframe. Legacy codec-12 HEVC is rewritten to Enhanced FLV. Video tags
/// holding only SEI/SPS/PPS/AUD are held back until a picture follows, so no
/// file ends with them. Files are written as `<name>.part` and renamed when
/// closed. Writes run in order in the background; [ready] applies
/// backpressure past 8 MiB and a write stuck for 30 s is fatal.
final class FlvSessionWriter {
  /// Creates a writer for [layout]; nothing touches the disk until the first keyframe.
  new({
    required this._files,
    required this.layout,
    required this.gaps,
    this.splitDuration,
    this.splitBytes,
    this.limits = const FlvWriterLimits(),
    this._onSegment,
  }) {
    _flushTimer = Timer.periodic(limits.flushInterval, (_) => _periodicFlush());
  }

  final RecordFiles _files;
  final void Function(SegmentEvent event)? _onSegment;

  /// Where the files go.
  final SessionLayout layout;

  /// The session's gap ledger.
  final GapLedger gaps;

  /// Split after this much media (at the next keyframe); null: never.
  final Duration? splitDuration;

  /// Split after this many bytes (at the next keyframe); null: never.
  final int? splitBytes;

  /// Limits.
  final FlvWriterLimits limits;

  final List<RecordedSegment> _segments = [];
  RecordedSegment? _segment;
  int _base = 0;

  bool? _headerAudio;
  bool? _headerVideo;
  var _audioOnly = false;
  var _sawVideo = false;
  var _audioWithoutVideo = 0;
  Uint8List? _script;
  Uint8List? _videoConfig;
  Uint8List? _audioConfig;
  Uint8List? _pendingVideoConfig;
  Uint8List? _pendingAudioConfig;
  var _splitRequested = false;

  var _offset = 0;
  int? _lastVideo;
  int? _lastAudio;
  var _needKeyframe = true;
  var _newConnection = false;
  DateTime? _lostAt;
  GapReason _lostReason = GapReason.eof;
  ({DateTime lostAt, int? missing})? _rebased;
  final _deltas = ListQueue<int>();
  ({int raw, int session, int? previous})? _lastKeyframe;

  final _held = <_Held>[];
  Completer<void>? _pictureWaiter;

  final _anchors = <({DateTime wall, int fileTs})>[];

  final _ops = ListQueue<_Op>();
  var _queued = 0;
  var _pumping = false;
  RecordSink? _sink;
  var _unflushed = 0;
  DateTime _lastFlush = clock.now();
  late final Timer _flushTimer;
  Completer<void>? _readyWaiter;
  final _failure = Completer<RecordFailure>();
  RecordFailure? _failed;
  var _closed = false;

  /// Media tags written in the session.
  int mediaTags = 0;

  /// Bytes written (or queued) to segment files.
  int get bytesWritten => _segments.fold(0, (sum, segment) => sum + segment.bytes);

  /// Media time written, summed over segments.
  Duration get mediaDuration => Duration(milliseconds: _segments.fold(0, (sum, segment) => sum + segment.durationMs));

  /// Segments so far, the open one last.
  List<RecordedSegment> get segments => List.unmodifiable(_segments);

  /// The segment being written, if any.
  RecordedSegment? get currentSegment => _segment;

  /// Completes with the fatal error that stopped writing, if one happens.
  Future<RecordFailure> get failure => _failure.future;

  /// The fatal error, once there is one.
  RecordFailure? get failed => _failed;

  /// Typical frame duration from recent video timestamps (1000/30 ms by default).
  int get frameDuration {
    if (_deltas.isEmpty) return 33;
    final sorted = _deltas.toList()..sort();
    return sorted[sorted.length ~/ 2];
  }

  /// Completes when the write queue is below its limit (backpressure, §6.8).
  Future<void> get ready {
    if (_queued < limits.queueBytes || _failed != null || _closed) return Future.value();
    return (_readyWaiter ??= Completer<void>()).future;
  }

  /// Whether video tags without a picture are waiting for one (§6.7).
  bool get holdsPrefix => _held.any((held) => held.video);

  /// Completes when no prefix-only video tag is held, or after [max].
  Future<void> waitForPicture(Duration max) {
    if (!holdsPrefix) return Future.value();
    final waiter = _pictureWaiter ??= Completer<void>();
    return waiter.future.timeout(max, onTimeout: () {});
  }

  /// Marks the start of a new upstream connection after the previous one was
  /// lost at [lostAt] for [reason]; its first media is aligned or rebased (§6.3).
  void beginConnection({DateTime? lostAt, GapReason reason = GapReason.eof}) {
    if (_lastVideo == null && _lastAudio == null) return;
    // Prefix-only video of the lost connection has no picture to come.
    for (final held in _held) {
      if (!held.video) _write(held.bytes, held.fileTs);
    }
    _held.clear();
    _newConnection = true;
    _needKeyframe = !_audioOnly;
    _lostAt = lostAt ?? clock.now();
    _lostReason = reason;
  }

  /// Notes that a splice switched connections at [switchAt] (splicer output
  /// timeline) after the old connection ended at [lostAt]: the skipped part
  /// becomes a gap (spec §5.1).
  void noteSplice({required int switchAt, required DateTime lostAt, required bool shifted}) {
    final keyframe = _lastKeyframe;
    final segment = _segment;
    if (keyframe == null || segment == null || keyframe.raw != switchAt) return;
    final previous = keyframe.previous;
    final step = previous == null ? 0 : keyframe.session - previous - frameDuration;
    final wall = clock.now().difference(lostAt).inMilliseconds;
    final missing = shifted ? (step > wall ? step : wall) : step;
    if (missing <= frameDuration) return;
    unawaited(
      gaps.add(
        RecordGap(
          part: segment.name,
          atMs: keyframe.session - _base,
          reason: GapReason.splice,
          wallStart: lostAt,
          wallEnd: clock.now(),
          missingMs: missing,
        ),
      ),
    );
  }

  /// File time in the current segment that corresponds to [wall] (chat
  /// timing, spec §17), clamped to what was written; null without a segment.
  int? fileTimeAt(DateTime wall) {
    final segment = _segment;
    if (segment == null || _anchors.isEmpty) return null;
    var anchor = _anchors.first;
    for (final candidate in _anchors) {
      if (candidate.wall.isAfter(wall)) break;
      anchor = candidate;
    }
    final value = anchor.fileTs + wall.difference(anchor.wall).inMilliseconds;
    return value.clamp(0, segment.durationMs);
  }

  /// Adds one packet (a file header or a complete tag). Never throws.
  void add(Uint8List packet) {
    if (_closed || _failed != null) return;
    try {
      _add(packet);
    } on Object catch (error) {
      _fail(RecordFailure(RecordErrorKind.inputDamaged, RecordStage.writer, 'bad packet: $error'));
    }
  }

  void _add(Uint8List packet) {
    if (packet.length >= 9 && packet[0] == 0x46 && packet[1] == 0x4C && packet[2] == 0x56) {
      if (_headerAudio == null) {
        _headerAudio = (packet[4] & 0x04) != 0;
        _headerVideo = (packet[4] & 0x01) != 0;
        _audioOnly = _headerVideo == false;
      }
      return;
    }
    if (packet.length < FlvTag.headerLength + 4) return;
    final tag = FlvCodec.rewriteLegacyHevc(packet);
    final type = FlvTag.type(tag);
    if (type == FlvTag.script) {
      _script ??= tag;
      return;
    }
    if (FlvTag.isVideoConfig(tag)) {
      _sawVideo = true;
      _onVideoConfig(tag);
      return;
    }
    if (FlvTag.isAudioConfig(tag)) {
      _onAudioConfig(tag);
      return;
    }
    if (type == FlvTag.video) {
      _sawVideo = true;
      _audioOnly = false;
      _onVideo(tag);
    } else if (type == FlvTag.audio) {
      if (!_sawVideo && !_audioOnly && ++_audioWithoutVideo > limits.audioOnlyAfter) {
        _audioOnly = true;
        _needKeyframe = false;
      }
      _onAudio(tag);
    }
  }

  void _onVideoConfig(Uint8List tag) {
    final current = _pendingVideoConfig ?? _videoConfig;
    if (current != null && FlvTag.samePayload(current, tag)) return;
    if (_segment == null || _videoConfig == null) {
      _videoConfig = tag;
      if (_segment != null) _writeTag(tag, _currentFileTs(video: true));
      return;
    }
    _pendingVideoConfig = tag;
  }

  void _onAudioConfig(Uint8List tag) {
    final current = _pendingAudioConfig ?? _audioConfig;
    if (current != null && FlvTag.samePayload(current, tag)) return;
    if (_segment == null || _audioConfig == null) {
      _audioConfig = tag;
      if (_segment != null) _writeTag(tag, _currentFileTs(video: false));
      return;
    }
    if (_audioOnly) {
      // No keyframes: switch at the next audio tag.
      _pendingAudioConfig = tag;
      _splitRequested = true;
      return;
    }
    _pendingAudioConfig = tag;
  }

  int _currentFileTs({required bool video}) {
    final last = video ? _lastVideo : _lastAudio;
    final value = (last ?? _base) - _base;
    return value < 0 ? 0 : value;
  }

  void _onVideo(Uint8List tag) {
    final keyframe = FlvTag.isKeyframe(tag);
    final raw = FlvTag.timestamp(tag);
    if (_needKeyframe) {
      if (!keyframe) return;
      if (_newConnection) _rebase(raw, video: true);
      _needKeyframe = false;
    }
    final ts = raw + _offset;
    final last = _lastVideo;
    if (last != null && ts < last) return;
    if (keyframe) {
      final split =
          _segment == null ||
          _pendingVideoConfig != null ||
          _pendingAudioConfig != null ||
          _splitRequested ||
          _limitReached(ts);
      if (split) _openSegment(ts);
      _lastKeyframe = (raw: raw, session: ts, previous: last);
      _noteRebase(ts);
    }
    if (_segment == null) return;
    if (last != null && ts > last) {
      _deltas.add(ts - last);
      if (_deltas.length > 32) _deltas.removeFirst();
    }
    _lastVideo = ts;
    final fileTs = ts - _base;
    final prefixOnly = FlvCodec.isPrefixOnly(tag, lengthSize: FlvCodec.naluLengthSize(_videoConfig));
    final bytes = FlvTag.withTimestamp(tag, fileTs);
    if (prefixOnly) {
      _held.add(_Held(bytes, video: true, fileTs: fileTs));
      return;
    }
    _releaseHeld();
    _write(bytes, fileTs);
    mediaTags++;
    final waiter = _pictureWaiter;
    _pictureWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _onAudio(Uint8List tag) {
    if (_pendingAudioConfig != null && !_audioOnly) return;
    final raw = FlvTag.timestamp(tag);
    if (_needKeyframe) return;
    if (_audioOnly && _newConnection) _rebase(raw, video: false);
    final ts = raw + _offset;
    final last = _lastAudio;
    if (last != null && ts <= last) return;
    if (_audioOnly && (_segment == null || _splitRequested || _limitReached(ts))) _openSegment(ts);
    if (_segment == null || ts < _base) return;
    if (_audioOnly) _noteRebase(ts);
    _lastAudio = ts;
    final fileTs = ts - _base;
    final bytes = FlvTag.withTimestamp(tag, fileTs);
    if (_held.isNotEmpty) {
      _held.add(_Held(bytes, video: false, fileTs: fileTs));
      return;
    }
    _write(bytes, fileTs);
    mediaTags++;
  }

  /// Whether the segment is due to split at a keyframe (or audio tag) at session time [ts].
  bool _limitReached(int ts) {
    final segment = _segment;
    if (segment == null) return false;
    final duration = splitDuration;
    if (duration != null && ts - _base >= duration.inMilliseconds) return true;
    final bytes = splitBytes;
    return bytes != null && segment.bytes >= bytes;
  }

  /// Aligns or rebases the first media tag of a new connection (§6.3); the
  /// gap is recorded by [_noteRebase] once the tag's segment is known.
  void _rebase(int raw, {required bool video}) {
    _newConnection = false;
    final last = video ? (_lastVideo ?? _lastAudio) : (_lastAudio ?? _lastVideo);
    final lostAt = _lostAt ?? clock.now();
    if (last == null) return;
    final frame = frameDuration;
    final candidate = raw + _offset;
    int missing;
    if (candidate > last && candidate - last <= limits.alignmentWindow.inMilliseconds) {
      missing = candidate - last - frame;
    } else {
      _offset = last + frame - raw;
      missing = clock.now().difference(lostAt).inMilliseconds;
    }
    _rebased = (lostAt: lostAt, missing: missing > frame ? missing : null);
  }

  void _noteRebase(int sessionTs) {
    final rebased = _rebased;
    final segment = _segment;
    if (rebased == null || segment == null) return;
    _rebased = null;
    final fileTs = sessionTs - _base;
    _anchors.add((wall: clock.now(), fileTs: fileTs));
    final missing = rebased.missing;
    if (missing == null) return;
    unawaited(
      gaps.add(
        RecordGap(
          part: segment.name,
          atMs: fileTs,
          reason: _lostReason,
          wallStart: rebased.lostAt,
          wallEnd: clock.now(),
          missingMs: missing,
        ),
      ),
    );
  }

  void _openSegment(int base) {
    final previous = _segment;
    if (previous != null) {
      // Prefix-only video before the split belongs to the dropped boundary.
      for (final held in _held) {
        if (!held.video) _write(held.bytes, held.fileTs);
      }
      _held.clear();
      _closeSegment(previous);
    }
    if (_pendingVideoConfig != null) _videoConfig = _pendingVideoConfig;
    if (_pendingAudioConfig != null) _audioConfig = _pendingAudioConfig;
    _pendingVideoConfig = null;
    _pendingAudioConfig = null;
    _splitRequested = false;
    final segment = RecordedSegment._(_segments.length + 1, layout.segment(_segments.length + 1));
    _segments.add(segment);
    _segment = segment;
    _base = base;
    _anchors
      ..clear()
      ..add((wall: clock.now(), fileTs: 0));
    _enqueue(_Open(segment));
    _write(FlvTag.fileHeader(audio: _headerAudio ?? true, video: !_audioOnly && (_headerVideo ?? true)), 0);
    final script = _script;
    if (script != null) _write(FlvTag.withTimestamp(script, 0), 0);
    final video = _videoConfig;
    if (video != null && !_audioOnly) _write(FlvTag.withTimestamp(video, 0), 0);
    final audio = _audioConfig;
    if (audio != null) _write(FlvTag.withTimestamp(audio, 0), 0);
    _onSegment?.call(SegmentOpened(segment));
  }

  void _closeSegment(RecordedSegment segment) {
    _enqueue(_Close(segment));
  }

  void _releaseHeld() {
    for (final held in _held) {
      _write(held.bytes, held.fileTs);
      mediaTags++;
    }
    _held.clear();
  }

  void _writeTag(Uint8List tag, int fileTs) => _write(FlvTag.withTimestamp(tag, fileTs), fileTs);

  void _write(Uint8List bytes, int fileTs) {
    final segment = _segment;
    if (segment == null) return;
    segment.bytes += bytes.length;
    if (fileTs > segment.durationMs) segment.durationMs = fileTs;
    _enqueue(_Write(bytes));
  }

  void _enqueue(_Op op) {
    _ops.add(op);
    if (op is _Write) _queued += op.bytes.length;
    if (!_pumping) unawaited(_pump());
  }

  void _periodicFlush() {
    if (_unflushed > 0 && _ops.isEmpty && !_pumping && _sink != null) _enqueue(const _Flush());
  }

  Future<void> _pump() async {
    _pumping = true;
    try {
      while (_ops.isNotEmpty && _failed == null) {
        final op = _ops.removeFirst();
        final stall = Timer(limits.stallTimeout, () {
          _fail(RecordFailure(RecordErrorKind.diskStalled, RecordStage.writer, 'write stalled'));
        });
        try {
          await _run(op);
        } on RecordFileExists catch (error) {
          _fail(RecordFailure(RecordErrorKind.pathInvalid, RecordStage.writer, error.toString()));
        } on FileSystemException catch (error) {
          _fail(classifyFileError(error));
        } on Object catch (error) {
          _fail(RecordFailure(RecordErrorKind.pathInvalid, RecordStage.writer, error.toString()));
        } finally {
          stall.cancel();
          if (op is _Write && _failed == null) {
            _queued -= op.bytes.length;
            if (_queued < limits.queueBytes) _wakeReady();
          }
        }
      }
    } finally {
      _pumping = false;
    }
  }

  Future<void> _run(_Op op) async {
    switch (op) {
      case _Open(:final segment):
        final path = await uniquePath(_files, segment.plannedPath);
        segment._path = path;
        _sink = await _files.create('$path$partSuffix');
        _unflushed = 0;
        _lastFlush = clock.now();
      case _Write(:final bytes):
        final sink = _sink;
        if (sink == null) return;
        await sink.write(bytes);
        _unflushed += bytes.length;
        if (_unflushed >= limits.flushBytes || clock.now().difference(_lastFlush) >= limits.flushInterval) {
          await sink.flush();
          _unflushed = 0;
          _lastFlush = clock.now();
        }
      case _Flush():
        final sink = _sink;
        if (sink == null || _unflushed == 0) return;
        await sink.flush();
        _unflushed = 0;
        _lastFlush = clock.now();
      case _Close(:final segment):
        final sink = _sink;
        _sink = null;
        if (sink != null) {
          await sink.flush();
          await sink.close();
          await _files.rename('${segment.path}$partSuffix', segment.path);
        }
        segment.closed = true;
        _onSegment?.call(SegmentClosed(segment));
      case _Barrier(:final done):
        done.complete();
    }
  }

  void _wakeReady() {
    final waiter = _readyWaiter;
    _readyWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  void _fail(RecordFailure failure) {
    if (_failed != null) return;
    _failed = failure;
    for (final op in _ops) {
      if (op is _Barrier && !op.done.isCompleted) op.done.complete();
    }
    _ops.clear();
    _queued = 0;
    _wakeReady();
    _failure.complete(failure);
  }

  /// Ends the session's output: drops held prefix-only video tags (§6.7),
  /// drains the queue and closes and renames the open segment. After a fatal
  /// error it still tries to close and rename the open file, giving up after
  /// [giveUpAfter].
  Future<List<RecordedSegment>> close({Duration giveUpAfter = const Duration(seconds: 10)}) async {
    if (_closed) return segments;
    _closed = true;
    _flushTimer.cancel();
    for (final held in _held) {
      if (!held.video) _write(held.bytes, held.fileTs);
    }
    _held.clear();
    final waiter = _pictureWaiter;
    _pictureWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    final segment = _segment;
    _segment = null;
    if (_failed == null) {
      if (segment != null) _enqueue(_Close(segment));
      final barrier = _Barrier();
      _enqueue(barrier);
      await barrier.done.future;
    }
    if (_failed != null && segment != null && !segment.closed) {
      // Best effort after a disk error: keep what reached the file.
      try {
        await Future(() async {
          final sink = _sink;
          _sink = null;
          await sink?.close();
          if (await _files.exists('${segment.path}$partSuffix')) {
            await _files.rename('${segment.path}$partSuffix', segment.path);
            segment.closed = true;
          }
        }).timeout(giveUpAfter);
      } on Object {
        // Left as .part; crash recovery finishes it at the next start.
      }
    }
    _wakeReady();
    return segments;
  }
}
