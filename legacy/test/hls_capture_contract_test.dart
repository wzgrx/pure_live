import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../tool/probes/hls_capture_contract.dart';
import '../tool/probes/media_packet_timeline.dart';

void main() {
  late Map diagnostics;
  late Map terminal;
  late Map output;
  late List<Map> sources;
  Map<String, Object?> audit() => auditHlsCaptureContract(
    diagnostics: diagnostics,
    terminal: terminal,
    outputTimeline: output,
    sourceTimelines: sources,
  );
  Map timeline(double videoSeconds, double audioSeconds, {double videoStart = 0}) => inspectMediaPacketTimeline({
    'streams': [
      {'index': 0, 'codec_type': 'video'},
      {'index': 1, 'codec_type': 'audio'},
    ],
    'packets': [
      {'stream_index': 0, 'pts_time': videoStart, 'dts_time': videoStart, 'duration_time': videoSeconds},
      {'stream_index': 1, 'pts_time': 0, 'dts_time': 0, 'duration_time': audioSeconds},
    ],
  });
  setUp(() {
    terminal = {
      'type': 'complete',
      'code': 0,
      'manualStop': true,
      'inputDrained': true,
      'inputCoverageIncomplete': false,
      'inputTailDiscarded': false,
      'inputIntegrityError': false,
      'forcedCancel': false,
    };
    Map segment(String id, int sequence, double seconds) => {
      'resourceId': id,
      'sequence': sequence,
      'duration': seconds,
      'programDateTime': '2026-09-10T00:00:00.000Z',
    };
    Map manifest(String feed, String id, double seconds) => {
      'resourceId': feed,
      'method': 'GET',
      'localStatus': 200,
      'deliveredMs': 1,
      'manifest': {
        'kind': 'media',
        'omittedSegments': 0,
        'omittedChildren': 0,
        'discontinuitySequence': 0,
        'segmentCount': 1,
        'segments': [segment(id, 100, seconds)],
      },
    };
    Map body(String id) => {
      'resourceId': id,
      'method': 'GET',
      'localStatus': 200,
      'bodyCompleteMs': 3,
      'deliveredMs': 4,
      'receivedBytes': 100,
      'outcome': 'completed',
    };
    diagnostics = {
      'schema': 1,
      'omittedRequests': 0,
      'requests': [
        {
          'manifest': {
            'kind': 'master',
            'omittedChildren': 0,
            'children': [
              {'resourceId': '1', 'role': 'variant'},
              {'resourceId': '2', 'role': 'audio'},
            ],
          },
        },
        manifest('1', 'a', 42),
        manifest('2', 'b', 44),
        body('a'),
        body('b'),
      ],
    };
    output = timeline(42, 44);
    sources = [timeline(42, 44)];
  });
  Map media(int index) => (diagnostics['requests'] as List)[index]['manifest'] as Map;
  Map track(String type) => (output['tracks'] as List).singleWhere((t) => t['type'] == type) as Map;

  test('complete offered content over forty seconds is measured against its source', () {
    final report = audit();
    expect(report['status'], 'passed');
    expect((report['feeds'] as List).first['expectedCoveredSeconds'], 42);
  });
  test('a file below forty seconds fails if it truncates offered content', () {
    output = timeline(38, 39);
    expect(audit()['failures'], containsAll(['output-video-end', 'output-audio-covered']));
  });
  test('A/V source phase is preserved instead of forcing both starts to zero', () {
    media(1)['segments'][0]['programDateTime'] = '2026-09-10T00:00:02.000Z';
    output = timeline(42, 44, videoStart: 2);
    expect(audit()['status'], 'passed');
    output = timeline(42, 44);
    expect(audit()['failures'], contains('output-video-start'));
  });
  test('matching outer envelope does not hide an interior packet hole', () {
    track('video')['knownMaxInternalGapSeconds'] = 2.0;
    track('video')['knownCoveredSeconds'] = 40.0;
    expect(audit()['failures'], containsAll(['output-internal-gap', 'output-video-covered']));
  });
  test('remux packet count conservation is independent of duration', () {
    track('video')['packets'] = 2;
    track('video')['knownIntervalPackets'] = 2;
    expect(audit()['failures'], contains('remux-video-packet-count'));
  });
  test('full source body means GET completion, not HEAD or headers only', () {
    final body = diagnostics['requests'][3] as Map;
    body['method'] = 'HEAD';
    expect(audit()['failures'], contains('undelivered-video-segment'));
    body['method'] = 'GET';
    body['bodyCompleteMs'] = null;
    expect(audit()['failures'], contains('undelivered-video-segment'));
  });
  test('a later successful delivery does not erase a local HTTP error', () {
    diagnostics['requests'].add({'resourceId': 'a', 'localStatus': 410});
    expect(audit()['failures'], contains('local-http-failure'));
  });
  for (final flag in ['inputCoverageIncomplete', 'inputTailDiscarded', 'inputIntegrityError', 'forcedCancel']) {
    test('native $flag stays a failing gate', () {
      terminal[flag] = true;
      expect(audit()['failures'], contains(flag));
    });
  }
  test('missing native flags and incomplete drain evidence do not pass', () {
    terminal.remove('inputTailDiscarded');
    terminal['inputDrained'] = false;
    expect(audit()['status'], 'incomplete');
  });
  test('missing packet duration prevents a complete clock verdict', () {
    track('audio')['completePresentationTimestamps'] = false;
    expect(audit()['status'], 'incomplete');
  });
  test('missing source files never count as known remux conservation', () {
    sources = [];
    expect(audit()['status'], isNot('passed'));
  });
  test('truncated request or segment history does not pass', () {
    diagnostics['omittedRequests'] = 1;
    expect(audit()['status'], 'incomplete');
    diagnostics['omittedRequests'] = 0;
    media(1)['omittedSegments'] = 1;
    expect(audit()['status'], 'incomplete');
  });
  test('multiple variants are not guessed into one recording feed', () {
    diagnostics['requests'][0]['manifest']['children'].add({'resourceId': '3', 'role': 'variant'});
    expect(audit()['status'], 'incomplete');
  });
  test('missing PDT and discontinuous PDT are explicit evidence gaps', () {
    media(1)['segments'][0]['programDateTime'] = null;
    expect(audit()['status'], isNot('passed'));
  });
  test('repeated generation deduplicates identical segments, not conflicting identities', () {
    final repeat = jsonDecode(jsonEncode(diagnostics['requests'][1])) as Map;
    diagnostics['requests'].add(repeat);
    expect(audit()['status'], 'passed');
    repeat['manifest']['segments'][0]['duration'] = 41;
    expect(audit()['failures'], contains('source-identity-changed'));
  });
  test('sequence and PDT continuity are separate constraints', () {
    final segments = media(1)['segments'] as List;
    segments.add({'resourceId': 'c', 'sequence': 102, 'duration': 2.0, 'programDateTime': '2026-09-10T00:00:45.000Z'});
    media(1)['segmentCount'] = 2;
    expect(audit()['failures'], contains('source-sequence-gap'));
    expect(audit()['missingEvidence'], contains('non-contiguous-source-pdt'));
  });
  test('output decode order is still checked', () {
    track('audio')['observedDtsRegressions'] = 1;
    expect(audit()['failures'], contains('output-dts-regression'));
  });
  test('damaged source-file clocks remain visible after a superficially clean remux', () {
    final source = (sources.single['tracks'] as List).first as Map;
    source['observedDtsRegressions'] = 1;
    source['knownMaxInternalGapSeconds'] = 2.0;
    expect(audit()['failures'], containsAll(['source-file-dts-regression', 'source-file-internal-gap']));
  });
  test('remux rounding tolerance stays bounded rather than scaling with file length', () {
    track('video')['knownPresentationEnd'] = 42.005333;
    expect(audit()['status'], 'passed');
    track('video')['knownPresentationEnd'] = 42.051;
    expect(audit()['failures'], contains('output-video-end'));
  });
  test('diagnostic report never echoes source metadata or URLs', () {
    media(1)['segments'][0]['secret'] = 'https://PRIVATE/token';
    expect(jsonEncode(audit()), isNot(contains('PRIVATE')));
  });
}
