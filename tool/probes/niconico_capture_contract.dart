import 'media_packet_timeline.dart';

/// Six-second probe contract, not source completeness or a long-recording gate.
/// Container duration and successful decoding alone miss a truncated audio tail.
Map<String, Object?> inspectNiconicoCapture(Map input) {
  final timeline = inspectMediaPacketTimeline(input);
  final failures = <String>[];
  final format = input['format'];
  final duration = format is Map ? double.tryParse('${format['duration']}') : null;
  if (duration == null || !duration.isFinite || duration < 5 || duration > 10) failures.add('container-duration');
  final tracks = (timeline['tracks'] as List).cast<Map<String, Object?>>();
  final video = tracks.where((track) => track['type'] == 'video').toList();
  final audio = tracks.where((track) => track['type'] == 'audio').toList();
  if (tracks.length != 2 || video.length != 1 || audio.length != 1) failures.add('track-selection');
  for (final track in tracks) {
    final type = track['type'];
    if (track['completePresentationTimestamps'] != true ||
        track['missingDtsPackets'] != 0 ||
        track['observedDtsRegressions'] != 0) {
      failures.add('$type-clock');
    }
    final covered = track['knownCoveredSeconds'];
    if (covered is! num || covered < 5 || covered > 10) failures.add('$type-duration');
    if (track['knownInternalGapCount'] != 0) failures.add('$type-gap');
  }
  final av = timeline['av'];
  if (av is! Map) {
    failures.add('av-clock');
  } else {
    if ((av['commonCoveredSeconds'] as num) < 5) failures.add('common-duration');
    if ((av['audioMinusVideoStartSeconds'] as num).abs() > 0.25) failures.add('av-start');
    if ((av['audioMinusVideoEndSeconds'] as num).abs() > 0.25) failures.add('av-tail');
  }
  return {'passed': failures.isEmpty, 'failures': failures, 'timeline': timeline};
}
