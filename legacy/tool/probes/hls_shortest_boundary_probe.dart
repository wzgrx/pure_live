part of 'hls_rolling_delivery_probe_test.dart';

void _registerShortestBoundaryProbe() {
  test(
    'shortest trims available track tails without completing the live HLS job before manual stop',
    () async {
      final fixture = Directory(Platform.environment['PURELIVE_ROLLING_HLS_FIXTURE']!);
      final root = await Directory(
        p.join(
          Platform.environment['PURELIVE_RECORDING_PROBE_OUTPUT']!,
          'shortest-${DateTime.now().microsecondsSinceEpoch}',
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
            (name: 'long-audio-preserved', video: 3, audio: 4, shortest: false, audioEnded: false),
            (name: 'long-audio-shortest', video: 3, audio: 4, shortest: true, audioEnded: false),
            (name: 'ended-audio-preserved', video: 4, audio: 3, shortest: false, audioEnded: true),
            (name: 'ended-audio-shortest', video: 4, audio: 3, shortest: true, audioEnded: true),
          ]) {
            reports.add(
              await _capture(
                (name: variant.name, budget: 5, bodyMs: 0, headerMs: 0, runSeconds: 4),
                fixture,
                root,
                productionPrefetch: true,
                fixedCounts: (video: variant.video, audio: variant.audio),
                distinctSequences: true,
                shortestOutput: variant.shortest,
                audioEnded: variant.audioEnded,
              ),
            );
          }
        }, _RealNetwork());
        Map track(int index, String type) =>
            ((reports[index]['inspection'] as Map)['tracks'] as List).singleWhere((track) => track['type'] == type)
                as Map;
        for (var i = 0; i < reports.length; i++) {
          final report = reports[i];
          expect(report['nativeShortest'], i.isOdd);
          final terminal = (report['events'] as List).last as Map;
          expect(terminal['type'], 'complete');
          expect(terminal['code'], 0);
          expect(report['stopIssued'], true);
          expect(terminal['manualStop'], true);
          expect(terminal['inputIntegrityError'], false);
          expect(report['inputCoverageIncomplete'], false);
          expect((report['prefetchAfterClose'] as Map)['entries'], 0);
          expect((report['prefetchAfterClose'] as Map)['bytes'], 0);
          expect((report['inspection'] as Map)['exitCode'], 0);
          expect((report['inspection'] as Map)['stderr'], '');
        }
        expect(track(0, 'video')['packets'], 180);
        expect(track(0, 'audio')['packets'], 375);
        expect(track(1, 'video')['packets'], track(0, 'video')['packets']);
        expect(track(1, 'audio')['packets'], 282);
        expect(
          ((track(1, 'audio')['lastPts'] as double) - (track(1, 'video')['lastPts'] as double)).abs(),
          lessThan(0.05),
        );
        expect(track(2, 'video')['packets'], 240);
        expect(track(2, 'audio')['packets'], 282);
        // Source ENDLIST does not establish early native job completion here:
        // the job still needs manual stop, but shortest has cut valid video.
        expect(track(3, 'video')['packets'], 179);
        expect(track(3, 'audio')['packets'], track(2, 'audio')['packets']);
      } finally {
        await File(p.join(root.path, 'summary.json'))
            .writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
        // ignore: avoid_print
        print('Native shortest-boundary evidence: ${root.path}');
        configureRecorderProxyRouting(null);
        Get.reset();
        await Hive.close();
      }
    },
    skip: Platform.environment['PURELIVE_HLS_SHORTEST_BOUNDARY_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
