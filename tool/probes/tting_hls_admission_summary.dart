import 'dart:convert';

import 'package:pure_live/recorder/services/hls_prefetch_plan.dart';
import 'package:pure_live/recorder/services/hls_retained_manifest.dart';
import 'package:pure_live/recorder/services/hls_retained_window.dart';

/// Metadata-only qualification of an already relayed manifest. Persist only
/// bounded tag names and numeric structure, never URLs or attribute text.
Map<String, Object?> ttingHlsAdmissionSummary(String text, Uri source) {
  final lines = const LineSplitter().convert(text);
  final tags = <String>{};
  final variants = <Map<String, int>>[];
  var parts = 0;
  for (final line in lines) {
    final tag = line.split(':').first;
    if (RegExp(r'^#EXT[A-Z0-9-]{0,64}$').hasMatch(tag) && tags.length < 64) tags.add(tag);
    if (tag == '#EXT-X-PART') parts++;
    if (tag == '#EXT-X-STREAM-INF' && variants.length < 16) {
      final dimensions = RegExp(r'(?:[:,])RESOLUTION=(\d{1,5})x(\d{1,5})(?:,|$)').firstMatch(line);
      final bandwidth = RegExp(r'(?:[:,])BANDWIDTH=(\d{1,12})(?:,|$)').firstMatch(line);
      variants.add({
        if (dimensions != null) 'width': int.parse(dimensions.group(1)!),
        if (dimensions != null) 'height': int.parse(dimensions.group(2)!),
        if (bandwidth != null) 'bandwidth': int.parse(bandwidth.group(1)!),
      });
    }
  }
  final result = <String, Object?>{'tags': tags.toList()..sort(), 'partialSegmentCount': parts};
  if (variants.isNotEmpty) {
    final plan = HlsPrefetchPlan.fromMaster(text, source);
    return result..addAll({
      'kind': 'master',
      'variants': variants,
      'unambiguousPlanAccepted': plan != null,
      'selectedFeedCount': plan?.sources.length ?? 0,
    });
  }
  result['kind'] = 'media';
  var stage = 'snapshot';
  try {
    final snapshot = HlsMediaSnapshot.parse(text, source);
    result.addAll({
      'snapshotParsed': true,
      'segmentCount': snapshot.segments.length,
      'targetDuration': snapshot.targetDuration,
      'version': snapshot.version,
      'pendingPartialCount': snapshot.lowLatency.pendingParts.length,
      'preloadHintCount': snapshot.lowLatency.preloadHints.length,
      'renditionReportCount': snapshot.lowLatency.renditionReports.length,
      'unhandledTags':
          snapshot.unhandledTags.where((tag) => RegExp(r'^#EXT[A-Z0-9-]{0,64}$').hasMatch(tag)).take(64).toList()
            ..sort(),
    });
    final window = HlsRetainedWindow(source);
    stage = 'retention';
    final evicted = window.merge(snapshot);
    stage = 'publication';
    renderHlsRetainedManifest(window, localUri: (uri) => uri);
    result['retentionAccepted'] = evicted.isEmpty;
    if (snapshot.lowLatency.partTarget != null && evicted.isEmpty) result['recordingMode'] = 'complete-parent-media';
  } on FormatException {
    result.putIfAbsent('snapshotParsed', () => false);
    result['retentionAccepted'] = false;
    result['failureStage'] = stage;
  }
  return result;
}
