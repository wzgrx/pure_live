part of 'hls_rolling_delivery_probe_test.dart';

void _registerRefreshCoverageProbe() {
  test(
    'native stop keeps active background refresh loss separate from successful body drain',
    () async {
      final fixture = Directory(Platform.environment['PURELIVE_ROLLING_HLS_FIXTURE']!);
      final root = await Directory(
        p.join(
          Platform.environment['PURELIVE_RECORDING_PROBE_OUTPUT']!,
          'refresh-${DateTime.now().microsecondsSinceEpoch}',
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
          for (final failure in [null, 'sequence-gap', 'http']) {
            reports.add(
              await _capture(
                (name: failure ?? 'healthy', budget: 5, bodyMs: 0, headerMs: 0, runSeconds: 3),
                fixture,
                root,
                productionPrefetch: true,
                fixedCounts: (video: 3, audio: 3),
                distinctSequences: true,
                failRefreshBeforeStop: failure,
              ),
            );
          }
        }, _RealNetwork());
        for (var i = 0; i < reports.length; i++) {
          final report = reports[i];
          final failed = i > 0;
          expect(report['inputCoverageIncomplete'], failed);
          expect(report['coverageWarningCount'], failed ? 1 : 0);
          final events = report['events'] as List;
          final terminal = events.last as Map;
          expect(terminal['type'], 'complete');
          expect(terminal['code'], 0);
          expect(terminal['inputDrained'], true);
          expect(terminal['forcedCancel'], false);
          expect(terminal['inputTailDiscarded'], false);
          expect(terminal['inputIntegrityError'], false);
          if (failed) {
            final event = events.singleWhere((event) => event['type'] == 'inputCoverage') as Map;
            expect(event['atMs'] as int, lessThanOrEqualTo(report['stopRequestedMs'] as int));
            final diagnostic = (report['refreshFailuresBeforeStop'] as List).single as Map;
            if (i == 1) expect(diagnostic['contract'], 'sequence-gap');
            if (i == 2) expect(diagnostic['upstreamStatus'], 503);
          }
          expect((report['prefetchAfterClose'] as Map)['entries'], 0);
          expect((report['prefetchAfterClose'] as Map)['bytes'], 0);
          final inspection = report['inspection'] as Map;
          expect(inspection['exitCode'], 0);
          expect(inspection['stderr'], '');
          expect(inspection['tracks'], (reports.first['inspection'] as Map)['tracks']);
        }
      } finally {
        await File(p.join(root.path, 'summary.json'))
            .writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
        // ignore: avoid_print
        print('Native refresh-coverage evidence: ${root.path}');
        configureRecorderProxyRouting(null);
        Get.reset();
        await Hive.close();
      }
    },
    skip: Platform.environment['PURELIVE_HLS_REFRESH_COVERAGE_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
