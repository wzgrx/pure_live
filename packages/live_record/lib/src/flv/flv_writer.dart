import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/src/errors.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/flv/flv_codec.dart';
import 'package:live_record/src/gaps.dart';
import 'package:live_record/src/naming.dart';
import 'package:live_record/src/segment_files.dart';
import 'package:live_record/src/writer.dart';

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
final class FlvSessionWriter implements SessionWriter {
  /// Creates a writer for [layout]; nothing touches the disk until the first
  /// keyframe. Segments are numbered from [firstIndex].
  new({
    required this._files,
    required this.layout,
    required this.gaps,
    this.splitDuration,
    this.splitBytes,
    this.limits = const FlvWriterLimits(),
    this.firstIndex = 1,
    this._onSegment,
  });

  final RecordFiles _files;
  final void Function(SegmentEvent event)? _onSegment;
  late final _out = SegmentFiles(_files, limits, onClosed: (segment) => _onSegment?.call(SegmentClosed(segment)));

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

  /// Number of the first segment (a session that switched from HLS continues its numbering).
  final int firstIndex;

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

  var _closed = false;

  /// Media tags written in the session.
  @override
  int mediaTags = 0;

  @override
  int get bytesWritten => _segments.fold(0, (sum, segment) => sum + segment.bytes);

  @override
  Duration get mediaDuration => Duration(milliseconds: _segments.fold(0, (sum, segment) => sum + segment.durationMs));

  @override
  List<RecordedSegment> get segments => List.unmodifiable(_segments);

  /// The segment being written, if any.
  RecordedSegment? get currentSegment => _segment;

  @override
  Future<RecordFailure> get failure => _out.failure;

  @override
  RecordFailure? get failed => _out.failed;

  /// Typical frame duration from recent video timestamps (1000/30 ms by default).
  int get frameDuration {
    if (_deltas.isEmpty) return 33;
    final sorted = _deltas.toList()..sort();
    return sorted[sorted.length ~/ 2];
  }

  @override
  Future<void> get ready => _closed ? Future.value() : _out.ready;

  /// Whether video tags without a picture are waiting for one (§6.7).
  bool get holdsPrefix => _held.any((held) => held.video);

  /// Completes when no prefix-only video tag is held, or after [max].
  @override
  Future<void> waitForPicture(Duration max) {
    if (!holdsPrefix) return Future.value();
    final waiter = _pictureWaiter ??= Completer<void>();
    return waiter.future.timeout(max, onTimeout: () {});
  }

  /// Marks the start of a new upstream connection after the previous one was
  /// lost at [lostAt] for [reason]; its first media is aligned or rebased (§6.3).
  @override
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
  @override
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
    if (_closed || _out.failed != null) return;
    try {
      _add(packet);
    } on Object catch (error) {
      _out.fail(RecordFailure(RecordErrorKind.inputDamaged, RecordStage.writer, 'bad packet: $error'));
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
    final index = firstIndex + _segments.length;
    final segment = RecordedSegment(index, layout.segment(index));
    _segments.add(segment);
    _segment = segment;
    _base = base;
    _anchors
      ..clear()
      ..add((wall: clock.now(), fileTs: 0));
    _out.open(segment);
    _write(FlvTag.fileHeader(audio: _headerAudio ?? true, video: !_audioOnly && (_headerVideo ?? true)), 0);
    final script = _script;
    if (script != null) _write(FlvTag.withTimestamp(script, 0), 0);
    final video = _videoConfig;
    if (video != null && !_audioOnly) _write(FlvTag.withTimestamp(video, 0), 0);
    final audio = _audioConfig;
    if (audio != null) _write(FlvTag.withTimestamp(audio, 0), 0);
    _onSegment?.call(SegmentOpened(segment));
  }

  void _closeSegment(RecordedSegment segment) => _out.close(segment);

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
    _out.write(bytes);
  }

  /// Ends the session's output: drops held prefix-only video tags (§6.7),
  /// drains the queue and closes and renames the open segment. After a fatal
  /// error it still tries to close and rename the open file, giving up after
  /// [giveUpAfter].
  @override
  Future<List<RecordedSegment>> close({Duration giveUpAfter = const Duration(seconds: 10)}) async {
    if (_closed) return segments;
    _closed = true;
    for (final held in _held) {
      if (!held.video) _write(held.bytes, held.fileTs);
    }
    _held.clear();
    final waiter = _pictureWaiter;
    _pictureWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    final segment = _segment;
    _segment = null;
    if (_out.failed == null) {
      if (segment != null) _out.close(segment);
      await _out.drain();
    }
    // Best effort after a disk error: keep what reached the file.
    if (_out.failed != null) await _out.salvage(segment, giveUpAfter);
    _out.stop();
    return segments;
  }
}
