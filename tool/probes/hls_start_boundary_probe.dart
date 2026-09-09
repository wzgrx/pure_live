part of 'hls_rolling_delivery_probe_test.dart';

// Compare native defaults against an explicit start index, using identical
// cached CMAF and a fixed live window. No production option is changed here.
void _registerStartBoundaryProbe() {
  test(
    'native per-playlist start index loses an available audio prefix in unequal live windows',
    () async {
      final fixture = Directory(Platform.environment['PURELIVE_ROLLING_HLS_FIXTURE']!);
      final root = await Directory(
        p.join(
          Platform.environment['PURELIVE_RECORDING_PROBE_OUTPUT']!,
          'start-${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create(recursive: true);
      Hive.init((await Directory(p.join(root.path, 'hive')).create()).path);
      await HivePrefUtil.init();
      Get.testMode = true;
      Get.put(LogController());
      configureRecorderProxyRouting((_) => 'DIRECT');
      final reports = <Map<String, Object?>>[];
      try {
        await HttpOverrides.runWithHttpOverrides(() async {
          for (final variant in [
            (name: 'equal-default', video: 3, audio: 3, index: null, distinct: false, hint: 0, sourceHint: false),
            (
              name: 'shared-unequal-default',
              video: 3,
              audio: 4,
              index: null,
              distinct: false,
              hint: 0,
              sourceHint: false,
            ),
            (
              name: 'distinct-unequal-default',
              video: 3,
              audio: 4,
              index: null,
              distinct: true,
              hint: 0,
              sourceHint: false,
            ),
            (
              name: 'distinct-unequal-zero',
              video: 3,
              audio: 4,
              index: 0,
              distinct: true,
              hint: null,
              sourceHint: false,
            ),
            (
              name: 'distinct-selected-hint',
              video: 3,
              audio: 4,
              index: null,
              distinct: true,
              hint: null,
              sourceHint: false,
            ),
            (
              name: 'distinct-unselected-hint',
              video: 3,
              audio: 4,
              index: null,
              distinct: true,
              hint: null,
              sourceHint: true,
            ),
            (
              name: 'distinct-explicit-hint',
              video: 3,
              audio: 4,
              index: null,
              distinct: true,
              hint: 1,
              sourceHint: true,
            ),
          ]) {
            final report = await _capture(
              (name: variant.name, budget: 5, bodyMs: 0, headerMs: 0, runSeconds: 4),
              fixture,
              root,
              productionPrefetch: true,
              fixedCounts: (video: variant.video, audio: variant.audio),
              liveStartIndex: variant.index,
              preferStartHint: variant.hint,
              sourceStartHint: variant.sourceHint,
              distinctSequences: variant.distinct,
            );
            reports.add(report);
            final snapshot =
                jsonDecode(await File(p.join(root.path, variant.name, 'hls-timeline.json')).readAsString()) as Map;
            report['nativeFirstSequences'] = _nativeFirstSequences(snapshot);
            expect(snapshot['prefetchRefreshFailures'], isEmpty);
            expect((report['prefetch'] as Map)['feeds'], variant.sourceHint ? 0 : 2);
            expect((report['prefetchAfterClose'] as Map)['entries'], 0);
            expect((report['prefetchAfterClose'] as Map)['bytes'], 0);
            expect(report['nativeStartIndex'], variant.index);
            expect(report['nativePreferStartHint'], variant.hint ?? (variant.index == null ? 1 : null));
            final terminal = (report['events'] as List).last as Map;
            expect(terminal['type'], 'complete');
            expect(terminal['code'], 0);
            expect(terminal['inputDrained'], true);
            expect(terminal['inputTailDiscarded'], false);
            expect(terminal['inputIntegrityError'], false);
            final inspection = report['inspection'] as Map;
            expect(inspection['exitCode'], 0);
            expect(inspection['stderr'], '');
            for (final track in inspection['tracks'] as List) {
              expect(track['packets'] as int, greaterThan(100));
              expect(track['maxStep'] as double, lessThan(0.05));
            }
          }
        }, _RealNetwork());
        Map track(int index, String type) =>
            ((reports[index]['inspection'] as Map)['tracks'] as List).singleWhere((track) => track['type'] == type)
                as Map;
        double startDifference(int index) =>
            (track(index, 'audio')['firstPts'] as double) - (track(index, 'video')['firstPts'] as double);
        expect(reports[0]['nativeFirstSequences'], {'video': 0, 'audio': 0});
        expect(reports[1]['nativeFirstSequences'], {'video': 1, 'audio': 1});
        expect(reports[2]['nativeFirstSequences'], {'video': 1000, 'audio': 2001});
        expect(reports[3]['nativeFirstSequences'], {'video': 1000, 'audio': 2000});
        expect(reports[4]['nativeFirstSequences'], {'video': 1000, 'audio': 2000});
        expect(reports[5]['nativeFirstSequences'], {'video': 1000, 'audio': 2001});
        expect(reports[6]['nativeFirstSequences'], {'video': 1000, 'audio': 2000});
        expect(startDifference(0).abs(), lessThan(0.05));
        expect(startDifference(1).abs(), lessThan(0.05));
        expect(startDifference(2), inExclusiveRange(1.9, 2.1));
        expect(startDifference(3).abs(), lessThan(0.05));
        expect(startDifference(4).abs(), lessThan(0.05));
        expect(startDifference(5), inExclusiveRange(1.9, 2.1));
        expect(startDifference(6).abs(), lessThan(0.05));
        for (final type in ['video', 'audio']) {
          expect(track(4, type), track(3, type));
          expect(track(5, type), track(2, type));
        }
        expect(track(3, 'audio')['packets'] as int, greaterThan(track(2, 'audio')['packets'] as int));
        expect(track(3, 'video')['packets'], track(2, 'video')['packets']);
        expect(track(1, 'video')['packets'] as int, lessThan(track(2, 'video')['packets'] as int));
        // Starting from zero recovers the prefix, not a common stop boundary.
        final endDifference = (track(3, 'audio')['lastPts'] as double) - (track(3, 'video')['lastPts'] as double);
        expect(endDifference, inExclusiveRange(1.9, 2.1));
      } finally {
        await File(p.join(root.path, 'summary.json'))
            .writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
        // ignore: avoid_print
        print('Native start-boundary evidence: ${root.path}');
        configureRecorderProxyRouting(null);
        Get.reset();
        await Hive.close();
      }
    },
    skip: Platform.environment['PURELIVE_HLS_START_BOUNDARY_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Map<String, int?> _nativeFirstSequences(Map snapshot) {
  final requests = snapshot['requests'] as List;
  final master = requests.firstWhere((r) => (r['manifest'] as Map?)?['kind'] == 'master')['manifest'] as Map;
  final result = <String, int?>{};
  for (final child in master['children'] as List) {
    final role = child['role'];
    if (role != 'audio' && role != 'variant') continue;
    final manifest = requests.firstWhere((r) => r['resourceId'] == child['resourceId'])['manifest'] as Map;
    final byId = {for (final s in manifest['segments'] as List) s['resourceId']: s['sequence'] as int};
    final first = requests.where((r) => byId.containsKey(r['resourceId']) && r['method'] == 'GET').firstOrNull;
    result[role == 'variant' ? 'video' : 'audio'] = first == null ? null : byId[first['resourceId']];
  }
  return result;
}
