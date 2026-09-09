import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/hls_prefetch_pool.dart';
import 'package:pure_live/recorder/services/hls_prefetch_scheduler.dart';

import 'ffmpeg_hls_prefetch_integration_test.dart' as http;
import 'hls_prefetch_scheduler_test.dart' as fixture;

void main() {
  for (final retention in [false, true]) {
    test('terminal refresh loss marks coverage once across two feeds; retention=$retention', () async {
      final pool = fixture.cache();
      final observed = Completer<void>();
      var failures = 0;
      var gaps = 0;
      var refreshes = 0;
      final scheduler = HlsPrefetchScheduler(
        pool: pool,
        pollInterval: const Duration(milliseconds: 10),
        fetchSnapshot: (_, _) async {
          refreshes++;
          if (!retention) throw const HandshakeException('private context');
          return fixture.snapshot(3, 1);
        },
        loadResource: (_, _) async => HlsPrefetchResponse(Stream.value([1])),
        onCoverageGap: () {
          gaps++;
          throw StateError('Coverage observer is not an owner');
        },
        onRefreshFailure: (_, _, _) {
          if (++failures == 2) observed.complete();
          throw StateError('Diagnostic observer is not an owner');
        },
      );
      try {
        expect(
          scheduler.selectAll([
            (id: 'video', source: fixture.source, snapshot: fixture.snapshot(0, 1)),
            (id: 'audio', source: fixture.source, snapshot: fixture.snapshot(0, 1)),
          ]),
          true,
        );
        final offered = scheduler.publish('video', (r) => r.uri);
        await observed.future.timeout(const Duration(seconds: 1));
        expect(scheduler.coverageIncomplete, true);
        expect(gaps, 1);
        scheduler.freeze();
        expect(scheduler.publish('video', (_) => throw StateError('Frozen remap')), '$offered#EXT-X-ENDLIST\n');
        expect(await scheduler.drainPublished(timeout: const Duration(seconds: 1)), true);
        // Complete cached bodies and incomplete temporal coverage are distinct.
        expect(scheduler.coverageIncomplete, true);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(refreshes, 2);
      } finally {
        await scheduler.close();
      }
      expect(pool.ownedEntries, 0);
      expect(pool.retainedBytes, 0);
    });
  }

  for (final stop in ['freeze', 'stopFetching', 'close']) {
    test('late refresh failure after $stop is cancellation, not coverage loss', () async {
      final pool = fixture.cache();
      final entered = Completer<void>();
      final released = Completer<void>();
      var gaps = 0;
      var failures = 0;
      final scheduler = HlsPrefetchScheduler(
        pool: pool,
        pollInterval: const Duration(milliseconds: 10),
        fetchSnapshot: (_, token) async {
          token.onCancel(released.complete);
          entered.complete();
          await released.future;
          throw const HttpException('Cancellation teardown');
        },
        loadResource: (_, _) async => HlsPrefetchResponse(Stream.value([1])),
        onCoverageGap: () => gaps++,
        onRefreshFailure: (_, _, _) => failures++,
      );
      try {
        expect(scheduler.select('video', fixture.source, fixture.snapshot(0, 1)), true);
        scheduler.publish('video', (r) => r.uri);
        await entered.future.timeout(const Duration(seconds: 1));
        switch (stop) {
          case 'freeze':
            scheduler.freeze();
          case 'stopFetching':
            scheduler.stopFetching();
          case 'close':
            await scheduler.close();
        }
        await scheduler.close().timeout(const Duration(seconds: 1));
        expect(released.isCompleted, true);
        expect(scheduler.coverageIncomplete, false);
        expect(gaps, 0);
        expect(failures, 0);
      } finally {
        await scheduler.close();
      }
      expect(pool.ownedEntries, 0);
      expect(pool.retainedBytes, 0);
    });
  }

  for (final failure in ['http', 'parse', 'sequence-gap']) {
    test('production relay reports $failure before another native playlist GET or stop', () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final jobs = <Future<void>>{};
      var manifests = 0;
      final sub = origin.listen((request) {
        late Future<void> job;
        job = () async {
          if (request.uri.path == '/index.m3u8') {
            manifests++;
            if (manifests > 1 && failure == 'http') {
              request.response.statusCode = 503;
            } else if (manifests > 1 && failure == 'parse') {
              request.response.write('malformed');
            } else {
              request.response.write(fixture.playlist(manifests > 1 ? 3 : 0, 1));
            }
          } else {
            request.response.add([1]);
          }
          await request.response.close();
        }().whenComplete(() => jobs.remove(job));
        jobs.add(job);
      });
      final diagnostics = HlsRelayDiagnostics();
      final relay = (await FFmpegHlsInputRelay.startForArguments(
        ['-i', 'http://127.0.0.1:${origin.port}/index.m3u8'],
        drainOnStop: true,
        enablePrefetch: true,
        diagnostics: diagnostics,
      ))!;
      var gaps = 0;
      relay.onCoverageIncomplete = () => gaps++;
      final client = HttpClient();
      try {
        final offered = utf8.decode((await http.get(client, relay.inputUri)).$2);
        final clock = Stopwatch()..start();
        while ((diagnostics.snapshot()['prefetchRefreshFailures']! as List).isEmpty &&
            clock.elapsed < const Duration(seconds: 2)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        final events = diagnostics.snapshot()['prefetchRefreshFailures']! as List;
        expect(events, hasLength(1));
        if (failure == 'sequence-gap') expect(events.single['contract'], 'sequence-gap');
        // No native retry/log is needed to make this loss visible.
        expect((diagnostics.snapshot()['requests']! as List), hasLength(1));
        expect(gaps, 1);
        await relay.finish();
        expect(utf8.decode((await http.get(client, relay.inputUri)).$2), '$offered#EXT-X-ENDLIST\n');
        expect((await http.get(client, http.mediaUris(offered).single)).$1, 200);
        expect(relay.inputTailDiscarded, false);
        expect(gaps, 1);
        expect(manifests, 2);
      } finally {
        client.close(force: true);
        await relay.close();
        await origin.close(force: true);
        await sub.cancel();
        await Future.wait(jobs.toList());
      }
      expect(relay.prefetchBodyCount, 0);
      expect(relay.prefetchBytes, 0);
    });
  }
}
