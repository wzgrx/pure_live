part of 'hls_rolling_delivery_probe_test.dart';

// Experimental HTTP adapter before the unchanged production relay/manager.
// This verifies sustained native delivery, not default production activation.
void _registerScheduledDeliveryProbe() {
  test(
    'independent prefetch sustains original 12s bodies and headers in the 6s native window',
    () async {
      final fixture = Directory(Platform.environment['PURELIVE_ROLLING_HLS_FIXTURE']!);
      final root = await Directory(
        p.join(
          Platform.environment['PURELIVE_RECORDING_PROBE_OUTPUT']!,
          'scheduled-${DateTime.now().microsecondsSinceEpoch}',
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
          for (final config in <_Scenario>[
            (name: 'scheduled-body-15', budget: 15, bodyMs: 12000, headerMs: 0, runSeconds: 34),
            (name: 'scheduled-headers-15', budget: 15, bodyMs: 0, headerMs: 12000, runSeconds: 34),
          ]) {
            reports.add(await _capture(config, fixture, root, scheduled: true));
          }
        }, _RealNetwork());
        for (final report in reports) {
          expect(report['started'], true);
          expect(report['inputCoverageIncomplete'], false);
          expect(report['receivedVideoSequenceGaps'], false);
          expect(report['completedUpstreamVideoRequests'] as int, greaterThanOrEqualTo(10));
          final terminal = (report['events'] as List).last as Map;
          expect(terminal['code'], 0);
          expect(terminal['forcedCancel'], false);
          expect(terminal['inputDrained'], true);
          expect(terminal['inputIntegrityError'], false);
          final prefetch = report['prefetch'] as Map;
          expect(prefetch['feeds'], 2);
          expect(prefetch['coverageIncomplete'], false);
          expect(prefetch['peakEntries'] as int, lessThanOrEqualTo(32));
          expect(prefetch['peakDownloads'] as int, lessThanOrEqualTo(16));
          expect(prefetch['refreshBeforeFirstVideoComplete'], true);
          expect((report['prefetchAfterClose'] as Map)['entries'], 0);
          expect((report['prefetchAfterClose'] as Map)['bytes'], 0);
          final inspection = report['inspection'] as Map;
          expect(inspection['exitCode'], 0);
          for (final track in inspection['tracks'] as List) {
            expect(track['packets'] as int, greaterThan(500));
            expect(track['maxStep'] as double, lessThan(0.05));
          }
        }
      } finally {
        await File(p.join(root.path, 'summary.json'))
            .writeAsString(const JsonEncoder.withIndent('  ').convert(reports));
        // ignore: avoid_print
        print(jsonEncode(reports));
        configureRecorderProxyRouting(null);
        Get.reset();
        await Hive.close();
      }
    },
    skip: Platform.environment['PURELIVE_HLS_SCHEDULED_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

final class _ScheduledRelay {
  _ScheduledRelay(this.server, this.origin, this.output, this.budget);
  final HttpServer server;
  final Uri origin;
  final Directory output;
  final int budget;
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  final cookies = HlsSessionCookies();
  late final HlsUpstreamClient transport;
  late final HlsPrefetchPool pool;
  late final HlsPrefetchScheduler scheduler;
  late final StreamSubscription<HttpRequest> subscription;
  final handlers = <Future<void>>{};
  final selections = <String, Future<void>>{};
  final resources = <String, HlsPrefetchResource>{};
  final ids = <String, String>{};
  final manifests = <String, String>{};
  Timer? drainTimer;
  bool finishing = false;
  bool closed = false;
  bool videoComplete = false;
  bool refreshBeforeFirstVideoComplete = false;
  int nextId = 0;
  int refreshes = 0;
  int peakEntries = 0;
  int peakDownloads = 0;
  Uri get input => Uri.parse('http://127.0.0.1:${server.port}/master.m3u8');

  static Future<_ScheduledRelay> start(Uri origin, Directory output, int budget) async {
    final owner = _ScheduledRelay(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), origin, output, budget);
    owner.transport = HlsUpstreamClient(client: owner.client, source: origin, headers: {}, cookies: owner.cookies);
    owner.pool = HlsPrefetchPool(
      createDirectory: () async => (await Directory(p.join(output.path, 'spool')).create()).createTemp('body-'),
      maximumEntries: 32,
      maximumConcurrent: 16,
      memoryBytesPerBody: 512 * 1024,
      bodyIdleTimeout: Duration(seconds: budget),
    );
    owner.scheduler = HlsPrefetchScheduler(
      pool: owner.pool,
      fetchSnapshot: (uri, token) async {
        owner.refreshes++;
        if (!owner.videoComplete) owner.refreshBeforeFirstVideoComplete = true;
        return owner.transport.loadSnapshot(uri, token, budget: owner.responseBudget());
      },
      loadResource: (resource, token) =>
          owner.transport.loadMedia(resource.uri, token, range: resource.range, budget: owner.responseBudget()),
      onDownloadResult: (resource, ready) {
        if (ready && resource.feedId == '/variant_0/index.m3u8') owner.videoComplete = true;
        owner.sample();
      },
    );
    owner.subscription = owner.server.listen((request) {
      late Future<void> job;
      job = owner.serve(request).whenComplete(() => owner.handlers.remove(job));
      owner.handlers.add(job);
    });
    return owner;
  }

  HlsResponseBudget responseBudget() => HlsResponseBudget(Duration(seconds: budget));
  void sample() {
    if (pool.ownedEntries > peakEntries) peakEntries = pool.ownedEntries;
    if (pool.activeDownloads > peakDownloads) peakDownloads = pool.activeDownloads;
  }

  Uri localUri(HlsPrefetchResource resource) {
    final id = ids.putIfAbsent(
      resource.key,
      () => '/cache/${nextId++}.${resource.kind == HlsPrefetchResourceKind.media ? 'm4s' : 'mp4'}',
    );
    resources[id] = resource;
    return input.resolve(id);
  }

  void pruneRegistry() {
    final required = scheduler.requiredKeys;
    for (final entry in resources.entries.toList()) {
      if (!required.contains(entry.value.key)) {
        resources.remove(entry.key);
        ids.remove(entry.value.key);
      }
    }
  }

  Future<void> select(String path) async {
    final uri = origin.resolve(path);
    final initial = await transport.loadSnapshot(uri, HlsPrefetchCancellation(), budget: responseBudget());
    if (!scheduler.select(path, uri, initial)) throw StateError('Fixture rendition unsupported');
    sample();
  }

  Future<void> serve(HttpRequest request) async {
    HlsPrefetchLease? lease;
    try {
      final path = request.uri.path;
      if (path == '/master.m3u8') {
        final (response, _) = await transport.open('GET', origin, budget: responseBudget());
        request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
        await request.response.addStream(response);
      } else if (path == '/variant_0/index.m3u8' || path == '/variant_1/index.m3u8') {
        await selections.putIfAbsent(path, () => select(path));
        final text = finishing ? manifests[path]! : scheduler.publish(path, localUri);
        manifests[path] = text;
        request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
        request.response.write(text);
        pruneRegistry();
      } else {
        final resource = resources[path];
        if (resource == null) {
          request.response.statusCode = 404;
        } else {
          lease = await scheduler.acquire(resource.key);
          if (lease == null) {
            request.response.statusCode = 503;
          } else {
            request.response.contentLength = lease.length;
            await lease.writeTo(request.response);
            await request.response.close();
            scheduler.delivered(resource.key);
            pruneRegistry();
          }
        }
      }
      await request.response.close();
    } on Object {
      try {
        request.response.statusCode = 502;
        await request.response.close();
      } on Object {
        /* Native may have closed this writer. */
      }
    } finally {
      await lease?.release();
      sample();
    }
  }

  void freeze() {
    if (finishing) return;
    finishing = true;
    scheduler.freeze();
    for (final path in manifests.keys.toList()) {
      if (!manifests[path]!.contains('#EXT-X-ENDLIST')) manifests[path] = '${manifests[path]}#EXT-X-ENDLIST\n';
    }
    drainTimer = Timer(const Duration(seconds: 2), () {
      scheduler.stopFetching();
      transport.stop();
      client.close(force: true);
    });
  }

  Map<String, Object?> snapshot() => {
    'feeds': scheduler.feedCount,
    'entries': pool.ownedEntries,
    'bytes': pool.retainedBytes,
    'peakEntries': peakEntries,
    'peakDownloads': peakDownloads,
    'refreshes': refreshes,
    'coverageIncomplete': scheduler.coverageIncomplete,
    'refreshBeforeFirstVideoComplete': refreshBeforeFirstVideoComplete,
    'scope': 'experimental prefetch adapter before unchanged production relay; local complete responses, not decoder acknowledgements',
  };
  Future<void> close() async {
    if (closed) return;
    closed = true;
    freeze();
    drainTimer?.cancel();
    scheduler.stopFetching();
    transport.stop();
    client.close(force: true);
    await server.close(force: true);
    await subscription.cancel();
    await Future.wait(handlers.toList());
    await scheduler.close();
    transport.clear();
    cookies.clear();
    resources.clear();
    ids.clear();
  }
}
