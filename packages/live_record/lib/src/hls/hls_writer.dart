import 'dart:async';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_record/src/errors.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/gaps.dart';
import 'package:live_record/src/hls/feed.dart';
import 'package:live_record/src/naming.dart';
import 'package:live_record/src/remux/ts_demux.dart';
import 'package:live_record/src/segment_files.dart';
import 'package:live_record/src/writer.dart';

/// Extension of MPEG-TS segment files.
const tsExtension = 'ts';

/// Extension of fMP4 segment files (initialisation section + fragments).
const fmp4Extension = 'm4s';

/// Writes one recording session's HLS media as continuous files (spec §7.5,
/// §8): the segments of a feed are appended whole and in sequence order, so
/// a file is one MPEG-TS stream (`<prefix>_<NNN>.ts`) or one fragmented MP4
/// (`<prefix>_<NNN>.m4s`: the initialisation section, then the fragments).
/// Segments are decrypted before they get here; keys never reach the disk.
///
/// A new file starts when the codec setup changes (MPEG-TS stream types,
/// parameter sets or AAC configuration; another fMP4 initialisation
/// section), when MPEG-TS and fMP4 alternate, or when `record.splitMinutes`
/// / `record.splitMegabytes` is reached (§6.5); at a segment boundary, or at
/// the segment's first keyframe when the segment does not start with one
/// (Amazon IVS), so every file starts with a keyframe. File time is the sum
/// of the written segments' `EXTINF`. Missing segments are
/// recorded in `gaps.json` at the current file time; the files keep the
/// upstream timestamps and the MP4 remux joins them (§10).
final class HlsSessionWriter implements SessionWriter, HlsSink {
  /// Creates a writer for [layout]; segments are numbered from [firstIndex].
  new({
    required this._files,
    required this.layout,
    required this.gaps,
    this.splitDuration,
    this.splitBytes,
    this.limits = const FlvWriterLimits(),
    this.firstIndex = 1,
    this.source = 'hls:video',
    this._onSegment,
  });

  final RecordFiles _files;
  final void Function(SegmentEvent event)? _onSegment;
  late final _out = SegmentFiles(_files, limits, onClosed: (segment) => _onSegment?.call(SegmentClosed(segment)));

  /// Where the files go.
  final SessionLayout layout;

  /// The session's gap ledger.
  final GapLedger gaps;

  /// Split after this much media (at the next segment); null: never.
  final Duration? splitDuration;

  /// Split after this many bytes (at the next segment); null: never.
  final int? splitBytes;

  /// Limits.
  final FlvWriterLimits limits;

  /// Number of the first segment (a session that switched from FLV continues its numbering).
  final int firstIndex;

  /// `source` of the gaps (`hls:video`).
  final String source;

  final List<RecordedSegment> _segments = [];
  RecordedSegment? _segment;
  String? _kind;
  Uint8List? _init;
  TsSignature? _signature;
  final _anchors = <({DateTime wall, int fileTs})>[];
  var _closed = false;

  /// Bytes dropped from segments that did not end on a whole MPEG-TS packet.
  int trimmedBytes = 0;

  @override
  int mediaTags = 0;

  @override
  int get bytesWritten => _segments.fold(0, (sum, segment) => sum + segment.bytes);

  @override
  Duration get mediaDuration => Duration(milliseconds: _segments.fold(0, (sum, segment) => sum + segment.durationMs));

  @override
  List<RecordedSegment> get segments => List.unmodifiable(_segments);

  /// The segment file being written, if any.
  RecordedSegment? get currentSegment => _segment;

  @override
  Future<RecordFailure> get failure => _out.failure;

  @override
  RecordFailure? get failed => _out.failed;

  @override
  Future<void> get ready => _closed ? Future.value() : _out.ready;

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

  /// Whole segments only: a file never ends in a cut picture.
  @override
  Future<void> waitForPicture(Duration max) => Future.value();

  /// Connections of an HLS feed continue by sequence number; the feed
  /// reports what is missing.
  @override
  void beginConnection({DateTime? lostAt, GapReason reason = GapReason.eof}) {}

  @override
  void addMedia(HlsMedia media) {
    if (_closed || _out.failed != null) return;
    final init = media.init;
    var data = media.data;
    String kind;
    TsSignature? signature;
    if (init != null) {
      kind = fmp4Extension;
    } else if (looksLikeTs(data)) {
      kind = tsExtension;
      final whole = data.length - data.length % tsPacketSize;
      if (whole != data.length) {
        trimmedBytes += data.length - whole;
        data = Uint8List.sublistView(data, 0, whole);
      }
      signature = TsSignature.of(data);
    } else {
      throw RecordException(
        RecordErrorKind.unsupportedProtocol,
        RecordStage.stream,
        'HLS segments that are neither MPEG-TS nor fMP4 (packed audio) are not recorded',
      );
    }
    final current = _signature;
    final newFile =
        _segment == null ||
        kind != _kind ||
        (init != null && !_sameInit(init)) ||
        (signature != null && current != null && !current.compatible(signature));
    final splitDue = !newFile && _limitReached;
    if ((newFile || splitDue) && signature != null && !signature.startsWithKeyframe) {
      // A file starts with a keyframe (§6.5): cut the segment at its first one.
      final cut = cutAtKeyframe(data);
      if (cut == null) {
        if (splitDue) {
          // No keyframe to split at: this segment stays in the current file.
          _append(data, media.durationMs);
          return;
        }
        if (_segment == null) {
          // Nothing decodable before the first keyframe of the recording.
          skippedSegments++;
          return;
        }
      } else {
        if (splitDue) {
          _append(cut.head, 0);
        } else {
          droppedBytes += cut.head.length;
        }
        _open(kind, init, signature);
        _append(cut.tail, media.durationMs);
        return;
      }
    }
    if (newFile || splitDue) {
      _open(kind, init, signature);
    } else if (signature != null && current != null) {
      _signature = current.merge(signature);
    }
    _append(data, media.durationMs);
  }

  /// Bytes left out in front of a file's first keyframe.
  int droppedBytes = 0;

  /// Segments left out before the recording's first keyframe.
  int skippedSegments = 0;

  void _append(Uint8List data, int durationMs) {
    final segment = _segment!;
    _anchors.add((wall: clock.now(), fileTs: segment.durationMs));
    if (_anchors.length > 64) _anchors.removeAt(0);
    _write(segment, data);
    segment.durationMs += durationMs;
    mediaTags++;
  }

  @override
  void addMissing(HlsMissing missing) {
    final segment = _segment;
    if (segment == null || _closed) return;
    unawaited(
      gaps.add(
        RecordGap(
          part: segment.name,
          atMs: segment.durationMs,
          reason: missing.reason,
          wallStart: missing.wallStart,
          wallEnd: clock.now(),
          missingMs: missing.missingMs,
          source: source,
          fromSeq: missing.fromSeq,
          toSeq: missing.toSeq,
        ),
      ),
    );
  }

  bool get _limitReached {
    final segment = _segment;
    if (segment == null) return false;
    final duration = splitDuration;
    if (duration != null && segment.durationMs >= duration.inMilliseconds) return true;
    final bytes = splitBytes;
    return bytes != null && segment.bytes >= bytes;
  }

  bool _sameInit(Uint8List init) {
    final current = _init;
    if (current == null) return false;
    if (identical(current, init)) return true;
    if (current.length != init.length) return false;
    for (var i = 0; i < init.length; i++) {
      if (current[i] != init[i]) return false;
    }
    return true;
  }

  void _open(String kind, Uint8List? init, TsSignature? signature) {
    final previous = _segment;
    if (previous != null) _out.close(previous);
    final index = firstIndex + _segments.length;
    final segment = RecordedSegment(index, layout.segment(index, extension: kind));
    _segments.add(segment);
    _segment = segment;
    _kind = kind;
    _init = init;
    _signature = signature;
    _anchors
      ..clear()
      ..add((wall: clock.now(), fileTs: 0));
    _out.open(segment);
    if (init != null) _write(segment, init);
    _onSegment?.call(SegmentOpened(segment));
  }

  void _write(RecordedSegment segment, Uint8List bytes) {
    segment.bytes += bytes.length;
    _out.write(bytes);
  }

  @override
  Future<List<RecordedSegment>> close({Duration giveUpAfter = const Duration(seconds: 10)}) async {
    if (_closed) return segments;
    _closed = true;
    final segment = _segment;
    _segment = null;
    if (_out.failed == null) {
      if (segment != null) _out.close(segment);
      await _out.drain();
    }
    if (_out.failed != null) await _out.salvage(segment, giveUpAfter);
    _out.stop();
    return segments;
  }
}
