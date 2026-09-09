import 'dart:math' as math;

/// Acceptance evidence for a bounded, single selected video/audio HLS capture.
/// This checks offered content, transport and packet clocks, not bitstream
/// identity or perceived A/V sync. Full decoding remains a separate gate.
Map<String, Object?> auditHlsCaptureContract({
  required Map diagnostics,
  required Map terminal,
  Map? outputTimeline,
  List<Map>? sourceTimelines,
}) {
  final failures = <String>{};
  final unknown = <String>{};
  final feeds = <String, _Feed>{};
  void require(bool condition, String code) {
    if (!condition) unknown.add(code);
  }

  if (terminal['type'] != 'complete' || terminal['code'] != 0 || terminal['manualStop'] != true) {
    failures.add('native-terminal');
  }
  for (final key in ['inputCoverageIncomplete', 'inputTailDiscarded', 'inputIntegrityError', 'forcedCancel']) {
    if (terminal[key] == true) failures.add(key);
    require(terminal[key] is bool, 'missing-native-flags');
  }
  require(terminal['inputDrained'] == true, 'input-not-drained');
  require(diagnostics['schema'] == 1 && diagnostics['omittedRequests'] == 0, 'incomplete-diagnostics');
  final requests = diagnostics['requests'];
  if (requests is! List || requests.length > 1024) {
    unknown.add('invalid-request-budget');
  } else {
    final masters = requests.whereType<Map>().where((r) => r['manifest'] is Map && r['manifest']['kind'] == 'master');
    for (final request in masters) {
      final manifest = request['manifest'] as Map;
      require(manifest['omittedChildren'] == 0, 'master-truncated');
      final children = manifest['children'];
      if (children is! List || children.length != 2) {
        unknown.add('ambiguous-selected-feeds');
        continue;
      }
      for (final child in children) {
        if (child is! Map || !_opaque(child['resourceId'])) {
          unknown.add('invalid-feed-id');
          continue;
        }
        final role = child['role'] == 'variant' ? 'video' : child['role'];
        if (role != 'video' && role != 'audio') {
          unknown.add('ambiguous-selected-feeds');
          continue;
        }
        final id = child['resourceId'] as String;
        if (feeds[id] != null && feeds[id]!.role != role) failures.add('feed-role-changed');
        feeds.putIfAbsent(id, () => _Feed(id, role as String));
      }
    }
    require(feeds.length == 2 && feeds.values.map((f) => f.role).toSet().length == 2, 'ambiguous-selected-feeds');
    final delivered = <String>{};
    for (final request in requests) {
      if (request is! Map) {
        unknown.add('invalid-request');
        continue;
      }
      if (request['localStatus'] is num && request['localStatus'] >= 400) failures.add('local-http-failure');
      if (request['method'] == 'GET' &&
          request['localStatus'] == 200 &&
          request['bodyCompleteMs'] is num &&
          request['deliveredMs'] is num &&
          request['receivedBytes'] is num &&
          request['receivedBytes'] > 0 &&
          request['outcome'] == 'completed') {
        if (_opaque(request['resourceId'])) delivered.add(request['resourceId'] as String);
      }
      final feed = feeds[request['resourceId']];
      final manifest = request['manifest'];
      if (feed == null || manifest is! Map || manifest['kind'] != 'media') continue;
      require(request['localStatus'] == 200 && request['deliveredMs'] is num, 'manifest-not-delivered');
      require(manifest['omittedSegments'] == 0 && manifest['omittedChildren'] == 0, 'media-truncated');
      final sequenceBase = manifest['discontinuitySequence'];
      require(sequenceBase is int, 'missing-discontinuity-sequence');
      if (feed.discontinuity != null && feed.discontinuity != sequenceBase) unknown.add('discontinuous-source');
      if (sequenceBase is int) feed.discontinuity ??= sequenceBase;
      final segments = manifest['segments'];
      if (segments is! List || segments.length > 64 || segments.length != manifest['segmentCount']) {
        unknown.add('invalid-manifest-segments');
        continue;
      }
      for (final raw in segments) {
        final segment = _Segment.parse(raw);
        if (segment == null) {
          unknown.add('missing-source-time-or-identity');
          continue;
        }
        final previous = feed.segments[segment.sequence];
        if (previous != null && !previous.same(segment)) failures.add('source-identity-changed');
        feed.segments.putIfAbsent(segment.sequence, () => segment);
      }
    }
    for (final feed in feeds.values) {
      final ordered = feed.ordered;
      require(ordered.isNotEmpty, 'empty-source-feed');
      for (var i = 0; i < ordered.length; i++) {
        final segment = ordered[i];
        if (!delivered.contains(segment.id)) failures.add('undelivered-${feed.role}-segment');
        if (i > 0) {
          if (segment.sequence != ordered[i - 1].sequence + 1) failures.add('source-sequence-gap');
          if ((segment.start - ordered[i - 1].end).abs() > 0.002) unknown.add('non-contiguous-source-pdt');
        }
      }
    }
  }

  final output = _tracks(outputTimeline);
  require(output != null, 'output-timeline-missing');
  require(
    sourceTimelines != null && sourceTimelines.isNotEmpty && sourceTimelines.length <= 32,
    'source-files-missing',
  );
  final anchor = feeds.values
      .where((f) => f.segments.isNotEmpty)
      .map((f) => f.ordered.first.start)
      .fold<double?>(null, (earliest, value) => earliest == null ? value : math.min(earliest, value));
  final rows = <Map<String, Object?>>[];
  for (final feed in feeds.values) {
    if (feed.segments.isEmpty || anchor == null) continue;
    final ordered = feed.ordered;
    final expectedStart = ordered.first.start - anchor;
    final expectedEnd = ordered.last.end - anchor;
    final expectedCovered = ordered.fold(0.0, (sum, s) => sum + s.duration);
    final tracks = output?.where((t) => t['type'] == feed.role).toList();
    require(tracks?.length == 1, 'ambiguous-output-tracks');
    final row = <String, Object?>{
      'role': feed.role,
      'feedId': feed.id,
      'firstSequence': ordered.first.sequence,
      'lastSequence': ordered.last.sequence,
      'segments': ordered.length,
      'expectedStartSeconds': expectedStart,
      'expectedEndSeconds': expectedEnd,
      'expectedCoveredSeconds': expectedCovered,
    };
    rows.add(row);
    if (tracks?.length != 1) continue;
    final track = tracks!.single;
    require(_complete(track), 'incomplete-output-packet-clock');
    if (_number(track['knownMaxInternalGapSeconds']) case final gap? when gap > 0.000002) {
      failures.add('output-internal-gap');
    }
    if (track['observedDtsRegressions'] != 0) failures.add('output-dts-regression');
    for (final check in [
      ('start', 'knownPresentationStart', expectedStart),
      ('end', 'knownPresentationEnd', expectedEnd),
      ('covered', 'knownCoveredSeconds', expectedCovered),
    ]) {
      final actual = _number(track[check.$2]);
      row['actual${check.$1}Seconds'] = actual;
      require(actual != null, 'missing-output-boundary');
      // Bounded packet-edge/remux tolerance, not a duration-dependent allowance.
      if (actual != null && (actual - check.$3).abs() > 0.05) failures.add('output-${feed.role}-${check.$1}');
    }
    var sourcePackets = 0;
    for (final timeline in (sourceTimelines ?? const <Map>[]).take(32)) {
      final sourceTracks = _tracks(timeline);
      require(sourceTracks != null, 'invalid-source-file-clock');
      final matching = sourceTracks?.where((t) => t['type'] == feed.role).toList() ?? [];
      require(matching.length <= 1, 'ambiguous-source-file-tracks');
      for (final source in matching) {
        require(_complete(source), 'incomplete-source-file-clock');
        if (source['observedDtsRegressions'] != 0) failures.add('source-file-dts-regression');
        if (_number(source['knownMaxInternalGapSeconds']) case final gap? when gap > 0.000002) {
          failures.add('source-file-internal-gap');
        }
        if (source['packets'] is int) sourcePackets += source['packets'] as int;
      }
    }
    row['sourceFilePackets'] = sourcePackets;
    row['outputPackets'] = track['packets'];
    if (sourcePackets != track['packets']) {
      failures.add('remux-${feed.role}-packet-count');
    }
  }
  return {
    'schema': 1,
    'scope': 'selected-contiguous-pdt-hls-delivery-and-packet-timeline-not-payload-or-decode',
    'status': failures.isNotEmpty
        ? 'failed'
        : unknown.isNotEmpty
        ? 'incomplete'
        : 'passed',
    'failures': failures.toList()..sort(),
    'missingEvidence': unknown.toList()..sort(),
    'boundaryToleranceSeconds': 0.05,
    'sourcePdtToleranceSeconds': 0.002,
    'feeds': rows,
  };
}

bool _opaque(Object? value) => value is String && RegExp(r'^(root|[0-9a-z]{1,16})$').hasMatch(value);
double? _number(Object? value) => value is num && value.isFinite ? value.toDouble() : null;
List<Map>? _tracks(Map? timeline) {
  final tracks = timeline?['tracks'];
  return tracks is List && tracks.length <= 32 && tracks.every((t) => t is Map) ? tracks.cast<Map>() : null;
}

bool _complete(Map t) =>
    t['completePresentationTimestamps'] == true &&
    t['missingDtsPackets'] == 0 &&
    t['packets'] is int &&
    t['packets'] > 0 &&
    t['knownIntervalPackets'] == t['packets'] &&
    t['observedDtsRegressions'] is int &&
    _number(t['knownMaxInternalGapSeconds']) != null;

class _Feed {
  _Feed(this.id, this.role);
  final String id;
  final String role;
  final segments = <int, _Segment>{};
  int? discontinuity;
  List<_Segment> get ordered => segments.values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
}

class _Segment {
  _Segment(this.id, this.sequence, this.start, this.duration);
  final String id;
  final int sequence;
  final double start;
  final double duration;
  double get end => start + duration;
  bool same(_Segment other) => id == other.id && duration == other.duration && start == other.start;
  static _Segment? parse(Object? value) {
    if (value is! Map || !_opaque(value['resourceId']) || value['sequence'] is! int || value['sequence'] < 0) {
      return null;
    }
    final duration = _number(value['duration']);
    final pdt = value['programDateTime'];
    final time = pdt is String && pdt.length <= 64 && RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(pdt)
        ? DateTime.tryParse(pdt)
        : null;
    if (duration == null || duration <= 0 || duration > 86400 || time == null) return null;
    return _Segment(
      value['resourceId'] as String,
      value['sequence'] as int,
      time.microsecondsSinceEpoch / 1000000,
      duration,
    );
  }
}
