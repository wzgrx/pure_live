import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/hls_body_reader.dart';
import 'package:pure_live/recorder/services/hls_prefetch_pool.dart';
import 'package:pure_live/recorder/services/hls_prefetch_scheduler.dart';
import 'package:pure_live/recorder/services/hls_retained_window.dart';
import 'package:pure_live/recorder/services/hls_session_cookies.dart';
import 'package:pure_live/recorder/services/hls_upstream_client.dart';

String playlist(int first, int count, {String prefix = '', bool ended = false}) =>
    '#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-MEDIA-SEQUENCE:$first\n'
    '${List.generate(count, (i) => '#EXTINF:1,\n$prefix${first + i}.m4s\n').join()}'
    '${ended ? '#EXT-X-ENDLIST\n' : ''}';
final source = Uri.parse('http://fixture.invalid/video/index.m3u8');
HlsMediaSnapshot snapshot(int first, int count, {bool ended = false}) =>
    HlsMediaSnapshot.parse(playlist(first, count, ended: ended), source);
HlsPrefetchPool cache({int entries = 32, int concurrent = 16}) => HlsPrefetchPool(
  createDirectory: () => throw StateError('Unexpected disk'),
  maximumEntries: entries,
  maximumConcurrent: concurrent,
  memoryBytesPerBody: 512 * 1024,
);
Future<List<int>> read(HlsPrefetchLease lease) async {
  final controller = StreamController<List<int>>();
  final bytes = controller.stream.fold<List<int>>([], (result, part) => result..addAll(part));
  try {
    await lease.writeTo(controller.sink);
  } finally {
    await controller.close();
    await lease.release();
  }
  return bytes;
}

void main() {
  test('first long feed reserves capacity for another feed; delivered prefix enables bounded continuation', () async {
    final pool = cache(entries: 8, concurrent: 8);
    final requests = <String>[];
    final scheduler = HlsPrefetchScheduler(
      pool: pool,
      fetchSnapshot: (_, _) => throw StateError('Ended feed refreshed'),
      loadResource: (resource, _) async {
        requests.add(resource.key);
        return HlsPrefetchResponse(Stream.value([resource.sequence!]));
      },
    );
    try {
      expect(scheduler.select('audio', source, snapshot(0, 10, ended: true)), true);
      expect(pool.ownedEntries, 4);
      expect(scheduler.select('video', source, snapshot(0, 10, ended: true)), true);
      expect(pool.ownedEntries, 8);
      expect(scheduler.select('third', source, snapshot(0, 10, ended: true)), false);
      expect(scheduler.feedCount, 2);
      for (final id in ['audio', 'video']) {
        scheduler.publish(id, (r) => Uri.parse('http://local.invalid/${Uri.encodeComponent(r.key)}'));
      }
      // The full finite publication must not pin all previously delivered data
      // forever, preventing admission of later segments that native needs.
      for (var sequence = 0; sequence < 10; sequence++) {
        for (final id in ['audio', 'video']) {
          final resource = HlsPrefetchResource.media(id, snapshot(sequence, 1).segments.single);
          final lease = await scheduler.acquire(resource.key).timeout(const Duration(seconds: 2));
          expect(lease, isNotNull, reason: '$id/$sequence');
          expect(await read(lease!), [sequence]);
          scheduler.delivered(resource.key);
        }
        expect(pool.ownedEntries, lessThanOrEqualTo(8));
      }
      expect(requests.length, 20);
      expect(requests.toSet().length, 20);
      expect(scheduler.coverageIncomplete, false);
    } finally {
      await scheduler.close();
    }
    expect(pool.ownedEntries, 0);
    expect(pool.retainedBytes, 0);
  });
  test('retired origin overlap is not resurrected and reused media URIs have per-sequence identities', () {
    final window = HlsRetainedWindow(source)..merge(snapshot(0, 4));
    window.retireBefore(2);
    window.merge(snapshot(0, 5));
    expect(window.segments.map((s) => s.sequence), [2, 3, 4]);
    final reused = HlsMediaSnapshot.parse(playlist(0, 2).replaceAll('1.m4s', '0.m4s'), source);
    final first = HlsPrefetchResource.media('a', reused.segments.first);
    final second = HlsPrefetchResource.media('a', reused.segments.last);
    expect(first.uri, second.uri);
    expect(first.key, isNot(second.key));
    expect(() => window.retireBefore(100), throwsArgumentError);
  });
  test('freeze cancels and awaits a late manifest without adding its new generation', () async {
    final pool = cache();
    final entered = Completer<void>();
    final late = Completer<HlsMediaSnapshot>();
    var cancelled = false;
    final scheduler = HlsPrefetchScheduler(
      pool: pool,
      pollInterval: const Duration(milliseconds: 10),
      fetchSnapshot: (_, token) {
        token.onCancel(() {
          cancelled = true;
        });
        entered.complete();
        return late.future;
      },
      loadResource: (r, _) async => HlsPrefetchResponse(Stream.value([r.sequence!])),
    );
    scheduler.select('video', source, snapshot(0, 3));
    await entered.future.timeout(const Duration(seconds: 2));
    final before = scheduler.publish('video', (r) => r.uri);
    scheduler.freeze();
    expect(cancelled, true);
    var closed = false;
    final closing = scheduler.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, false);
    late.complete(snapshot(1, 3));
    await closing;
    expect(before, isNot(contains('/3.m4s')));
    expect(pool.ownedEntries, 0);
  });
  test('unsupported inputs start no downloads and failed refresh is exposed rather than served indefinitely', () async {
    final pool = cache();
    var downloads = 0;
    final refreshed = Completer<void>();
    final scheduler = HlsPrefetchScheduler(
      pool: pool,
      pollInterval: const Duration(milliseconds: 10),
      fetchSnapshot: (_, _) async {
        refreshed.complete();
        throw const FormatException('Changed source fixture');
      },
      loadResource: (r, _) async {
        downloads++;
        return HlsPrefetchResponse(Stream.value([1]));
      },
    );
    try {
      final unsupported = HlsMediaSnapshot.parse('${playlist(0, 1)}#EXT-X-PART:DURATION=0.2,URI="p.m4s"\n', source);
      expect(scheduler.select('unsupported', source, unsupported), false);
      expect(downloads, 0);
      scheduler.select('video', source, snapshot(0, 1));
      await refreshed.future;
      await Future<void>.delayed(Duration.zero);
      expect(() => scheduler.publish('video', (r) => r.uri), throwsStateError);
    } finally {
      await scheduler.close();
    }
  });
  test(
    'stop preserves a complete body for drain while cancelling incomplete media without a capture-gap warning',
    () async {
      final pool = cache();
      final pending = StreamController<List<int>>();
      var cancelled = false;
      pending.onCancel = () {
        cancelled = true;
      };
      final scheduler = HlsPrefetchScheduler(
        pool: pool,
        fetchSnapshot: (_, _) => throw StateError('Ended feed refreshed'),
        loadResource: (r, _) async => HlsPrefetchResponse(r.sequence == 0 ? Stream.value([1]) : pending.stream),
      );
      try {
        scheduler.select('video', source, snapshot(0, 2, ended: true));
        final first = HlsPrefetchResource.media('video', snapshot(0, 1).segments.single);
        expect(await read((await scheduler.acquire(first.key))!), [1]);
        scheduler.stopFetching();
        expect(await read((await scheduler.acquire(first.key))!), [1]);
        await scheduler.close();
        expect(cancelled, true);
        expect(scheduler.coverageIncomplete, false);
      } finally {
        await scheduler.close();
        await pending.close();
      }
    },
  );
  test(
    'rolling HTTP snapshots prefetch both selected tracks before expiry while slow bodies remain in flight',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final clock = Stopwatch()..start();
      final base = Uri.parse('http://127.0.0.1:${server.port}/');
      final firstByTrack = <String, int>{};
      final requested = <String>[];
      var expired = 0;
      var manifestCount = 0;
      var firstComplete = false;
      var refreshBeforeFirstBody = false;
      final jobs = <Future<void>>{};
      final release = Completer<void>();
      final subscription = server.listen((request) {
        late Future<void> job;
        job = () async {
          try {
            final track = request.uri.pathSegments.first;
            if (request.uri.path.endsWith('.m3u8')) {
              manifestCount++;
              if (manifestCount > 2 && !firstComplete) refreshBeforeFirstBody = true;
              final first = clock.elapsedMilliseconds ~/ 120;
              firstByTrack[track] = first;
              request.response.write(playlist(first, 3));
            } else {
              final sequence = int.parse(request.uri.pathSegments.last.split('.').first);
              requested.add('$track/$sequence');
              if (sequence < clock.elapsedMilliseconds ~/ 120) {
                expired++;
                request.response.statusCode = 410;
              } else {
                await Future.any([Future<void>.delayed(const Duration(milliseconds: 600)), release.future]);
                firstComplete = true;
                request.response.contentLength = 1;
                request.response.add([sequence]);
              }
            }
            await request.response.close();
          } on Object {
            /* A fixture request may be cancelled during teardown. */
          }
        }().whenComplete(() => jobs.remove(job));
        jobs.add(job);
      });
      final transport = HlsUpstreamClient(
        client: client,
        source: base.resolve('master.m3u8'),
        headers: {},
        cookies: HlsSessionCookies(),
      );
      final pool = cache();
      final scheduler = HlsPrefetchScheduler(
        pool: pool,
        pollInterval: const Duration(milliseconds: 30),
        fetchSnapshot: (uri, token) =>
            transport.loadSnapshot(uri, token, budget: HlsResponseBudget(const Duration(seconds: 2))),
        loadResource: (resource, token) =>
            transport.loadMedia(resource.uri, token, budget: HlsResponseBudget(const Duration(seconds: 2))),
      );
      final local = <Uri, HlsPrefetchResource>{};
      final beginnings = <String, int>{};
      Uri localUri(HlsPrefetchResource resource) {
        final uri = Uri.parse('http://native.invalid/${Uri.encodeComponent(resource.key)}.m4s');
        local[uri] = resource;
        return uri;
      }

      try {
        for (final track in ['audio', 'video']) {
          final uri = base.resolve('$track/index.m3u8');
          final initial = await transport.loadSnapshot(
            uri,
            HlsPrefetchCancellation(),
            budget: HlsResponseBudget(const Duration(seconds: 2)),
          );
          beginnings[track] = initial.segments.first.sequence;
          expect(scheduler.select(track, uri, initial), true);
        }
        for (var step = 0; step < 13; step++) {
          for (final track in ['audio', 'video']) {
            final sequence = beginnings[track]! + step;
            HlsSegmentDescriptor? target;
            final wait = Stopwatch()..start();
            while (target == null && wait.elapsed < const Duration(seconds: 3)) {
              final text = scheduler.publish(track, localUri);
              final parsed = HlsMediaSnapshot.parse(text, base.resolve('$track/index.m3u8'));
              for (final segment in parsed.segments) {
                if (segment.sequence == sequence) target = segment;
              }
              if (target == null) await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            expect(target, isNotNull, reason: '$track/$sequence in published manifest');
            final resource = local[target!.uri]!;
            final lease = await scheduler.acquire(resource.key).timeout(const Duration(seconds: 3));
            expect(lease, isNotNull, reason: '$track/$sequence retained before expiry');
            expect(await read(lease!), [sequence]);
            scheduler.delivered(resource.key);
            expect(pool.ownedEntries, lessThanOrEqualTo(32));
            expect(pool.activeDownloads, lessThanOrEqualTo(16));
          }
        }
        expect(refreshBeforeFirstBody, true);
        expect(expired, 0);
        expect(scheduler.coverageIncomplete, false);
        expect(requested.toSet().length, requested.length);
        expect(manifestCount, greaterThan(10));
        expect(firstByTrack.keys, unorderedEquals(['audio', 'video']));
      } finally {
        scheduler.stopFetching();
        transport.stop();
        client.close(force: true);
        release.complete();
        await scheduler.close();
        transport.clear();
        await server.close(force: true);
        await subscription.cancel();
        await Future.wait(jobs.toList());
      }
      expect(pool.ownedEntries, 0);
      expect(pool.retainedBytes, 0);
    },
  );
}
