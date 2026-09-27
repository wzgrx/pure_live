import 'dart:math' as math;

/// Packet-clock evidence for short acceptance captures, not a decoder or a
/// source-completeness verdict. PTS reordering is valid; DTS order is checked
/// separately. Missing durations are unknown, never guessed from nominal FPS.
/// Codec priming/edit lists and perceived lip sync need separate validation.
Map<String, Object?> inspectMediaPacketTimeline(Map input) {
  final streams = input['streams'];
  final packets = input['packets'];
  if (streams is! List || packets is! List || streams.length > 32 || packets.length > 100000) {
    throw const FormatException('Packet timeline input shape or budget');
  }
  final tracks = <int, _Track>{};
  for (final stream in streams) {
    if (stream is! Map || stream['index'] is! int || stream['codec_type'] is! String) {
      throw const FormatException('Packet timeline stream descriptor');
    }
    final index = stream['index'] as int;
    if (index < 0 || tracks.containsKey(index)) throw const FormatException('Packet timeline stream index');
    tracks[index] = _Track(index, stream['codec_type'] as String);
  }
  for (final packet in packets) {
    if (packet is! Map || packet['stream_index'] is! int || !tracks.containsKey(packet['stream_index'])) {
      throw const FormatException('Packet timeline undeclared stream');
    }
    tracks[packet['stream_index']]!.add(packet);
  }
  for (final track in tracks.values) {
    track.finish();
  }
  final video = tracks.values.where((track) => track.type == 'video').toList();
  final audio = tracks.values.where((track) => track.type == 'audio').toList();
  Map<String, Object?>? av;
  if (video.length == 1 && audio.length == 1 && video.single.complete && audio.single.complete) {
    final v = video.single;
    final a = audio.single;
    av = {
      'audioMinusVideoStartSeconds': a.ranges.first.start - v.ranges.first.start,
      'audioMinusVideoEndSeconds': a.ranges.last.end - v.ranges.last.end,
      // Intersect actual covered intervals, not just the outer envelopes.
      'commonCoveredSeconds': _intersection(v.ranges, a.ranges),
      'videoCoveredSeconds': v.covered,
      'audioCoveredSeconds': a.covered,
    };
  }
  return {
    'schema': 1,
    'scope': 'packet-presentation-intervals-not-decode-or-source-completeness',
    'roundingToleranceSeconds': _roundingTolerance,
    'tracks': tracks.values.map((track) => track.report()).toList(),
    'av': av,
    'avUnavailableReason': av != null
        ? null
        : video.length != 1 || audio.length != 1
        ? 'requires-one-video-and-one-audio-stream'
        : 'empty-or-incomplete-packet-timestamps',
  };
}

// ffprobe *_time values are rounded to microseconds. This only coalesces
// rounding seams; substantive holes remain measured, with no pass threshold.
const _roundingTolerance = 0.000002;
typedef _Range = ({double start, double end});

double? _time(Object? value) {
  final parsed = value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;
  return parsed?.isFinite == true ? parsed : null;
}

class _Track {
  _Track(this.index, this.type);
  final int index;
  final String type;
  final intervals = <_Range>[];
  final ranges = <_Range>[];
  int count = 0;
  int missingPts = 0;
  int missingDuration = 0;
  int missingDts = 0;
  int dtsRegressions = 0;
  double? previousDts;
  double? firstPts;
  double? lastPts;
  double maxPtsStep = 0;
  double maxInternalGap = 0;
  double totalInternalGap = 0;
  int internalGaps = 0;
  final times = <double>[];

  bool get complete => count > 0 && intervals.length == count;
  double get covered => ranges.fold(0.0, (sum, range) => sum + range.end - range.start);

  void add(Map packet) {
    count++;
    final pts = _time(packet['pts_time']);
    final dts = _time(packet['dts_time']);
    final duration = _time(packet['duration_time']);
    if (pts == null) {
      missingPts++;
    } else {
      times.add(pts);
    }
    if (duration == null || duration <= 0) missingDuration++;
    if (pts != null && duration != null && duration > 0 && (pts + duration).isFinite && pts + duration > pts) {
      intervals.add((start: pts, end: pts + duration));
    }
    if (dts == null) {
      missingDts++;
    } else {
      if (previousDts != null && dts < previousDts! - _roundingTolerance) dtsRegressions++;
      previousDts = dts;
    }
  }

  void finish() {
    times.sort();
    firstPts = times.firstOrNull;
    lastPts = times.lastOrNull;
    for (var i = 1; i < times.length; i++) {
      maxPtsStep = math.max(maxPtsStep, times[i] - times[i - 1]);
    }
    intervals.sort((a, b) => a.start.compareTo(b.start));
    for (final next in intervals) {
      if (ranges.isEmpty) {
        ranges.add(next);
        continue;
      }
      final previous = ranges.last;
      final gap = next.start - previous.end;
      if (gap <= _roundingTolerance) {
        ranges[ranges.length - 1] = (start: previous.start, end: math.max(previous.end, next.end));
      } else {
        internalGaps++;
        totalInternalGap += gap;
        maxInternalGap = math.max(maxInternalGap, gap);
        ranges.add(next);
      }
    }
  }

  Map<String, Object?> report() => {
    'index': index,
    'type': type,
    'packets': count,
    'firstPts': firstPts,
    'lastPts': lastPts,
    'maxStep': maxPtsStep,
    'knownIntervalPackets': intervals.length,
    'completePresentationTimestamps': complete,
    'missingPtsPackets': missingPts,
    'missingOrInvalidDurationPackets': missingDuration,
    'missingDtsPackets': missingDts,
    'observedDtsRegressions': dtsRegressions,
    'knownPresentationStart': ranges.firstOrNull?.start,
    'knownPresentationEnd': ranges.lastOrNull?.end,
    'knownCoveredSeconds': covered,
    'knownInternalGapCount': internalGaps,
    'knownInternalGapSeconds': totalInternalGap,
    'knownMaxInternalGapSeconds': maxInternalGap,
  };
}

double _intersection(List<_Range> left, List<_Range> right) {
  var i = 0;
  var j = 0;
  double common = 0;
  while (i < left.length && j < right.length) {
    common += math.max(0.0, math.min(left[i].end, right[j].end) - math.max(left[i].start, right[j].start));
    if (left[i].end < right[j].end) {
      i++;
    } else {
      j++;
    }
  }
  return common;
}
