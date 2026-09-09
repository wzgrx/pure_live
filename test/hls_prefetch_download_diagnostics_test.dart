import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/hls_prefetch_pool.dart';

void main() {
  HlsPrefetchPool pool({bool enabled = true, int concurrent = 1}) => HlsPrefetchPool(
    createDirectory: () => throw StateError('Unexpected disk'),
    maximumEntries: 2,
    maximumConcurrent: concurrent,
    enableDiagnostics: enabled,
  );
  Future<HlsPrefetchResponse> value(HlsPrefetchCancellation _) async =>
      HlsPrefetchResponse(Stream.value([1, 2]), expectedLength: 2);

  test('queued and loading tickets remain distinguishable through cancellation', () async {
    final owner = pool();
    final headers = Completer<HlsPrefetchResponse>();
    final loading = owner.prefetch('private-url-token', (cancel) {
      cancel.onCancel(() => headers.completeError(StateError('private-error')));
      return headers.future;
    })!;
    final queued = owner.prefetch('queued', value)!;
    expect(loading.diagnosticsSnapshot()!['phase'], 'loading');
    expect(loading.diagnosticsSnapshot()!['headersMs'], isNull);
    expect(queued.diagnosticsSnapshot()!['phase'], 'queued');
    expect(queued.diagnosticsSnapshot()!['loadStartedMs'], isNull);
    await owner.close();
    expect(loading.diagnosticsSnapshot()!['retiredPhase'], 'loading');
    expect(queued.diagnosticsSnapshot()!['retiredPhase'], 'queued');
    expect(loading.diagnosticsSnapshot()!['failure'], 'cancelled');
    expect(queued.diagnosticsSnapshot()!['disposed'], true);
    expect(jsonEncode(loading.diagnosticsSnapshot()), isNot(contains('private')));
    expect(owner.ownedEntries, 0);
  });

  test('partial body progress is detached and complete body becomes ready', () async {
    final owner = pool();
    final body = StreamController<List<int>>();
    final ticket = owner.prefetch('key', (_) async => HlsPrefetchResponse(body.stream, expectedLength: 4))!;
    try {
      body.add([1, 2]);
      await until(() => ticket.diagnosticsSnapshot()!['stagedBytes'] == 2);
      final before = ticket.diagnosticsSnapshot()!;
      expect(before['phase'], 'body');
      expect(before['expectedBytes'], 4);
      expect(before['receivedBytes'], 2);
      expect(before['firstBodyMs'], isNotNull);
      expect(before['sealedMs'], isNull);
      before['receivedBytes'] = 999;
      expect(ticket.diagnosticsSnapshot()!['receivedBytes'], 2);
      body.add([3, 4]);
      await body.close();
      expect(await ticket.ready, true);
      final after = ticket.diagnosticsSnapshot()!;
      expect(after['phase'], 'ready');
      expect(after['stagedBytes'], 4);
      expect(after['sealedMs'], greaterThanOrEqualTo(after['lastBodyMs'] as int));
    } finally {
      await owner.close();
    }
  });

  test('disabled observation allocates no ticket trace', () async {
    final owner = pool(enabled: false);
    try {
      final ticket = owner.prefetch('key', value)!;
      expect(await ticket.ready, true);
      expect(ticket.diagnosticsSnapshot(), isNull);
    } finally {
      await owner.close();
    }
  });

  test('late loader timestamps stay monotonic after retirement', () async {
    final owner = pool();
    final response = Completer<HlsPrefetchResponse>();
    final ticket = owner.prefetch('late', (_) => response.future)!;
    final closing = owner.close();
    final retired = ticket.diagnosticsSnapshot()!['retiredMs'] as int;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    response.complete(await value(HlsPrefetchCancellation()));
    await closing;
    final state = ticket.diagnosticsSnapshot()!;
    expect(state['retiredPhase'], 'loading');
    expect(state['headersMs'], greaterThanOrEqualTo(retired + 10));
    expect(state['disposed'], true);
    expect(state['failure'], 'cancelled');
  });

  test('body cancellation retains partial progress and failure stage', () async {
    final owner = pool();
    final body = StreamController<List<int>>();
    final ticket = owner.prefetch('key', (_) async => HlsPrefetchResponse(body.stream, expectedLength: 4))!;
    body.add([1, 2]);
    await until(() => ticket.diagnosticsSnapshot()!['stagedBytes'] == 2);
    await owner.close();
    await body.close();
    final state = ticket.diagnosticsSnapshot()!;
    expect(state['retiredPhase'], 'body');
    expect(state['receivedBytes'], 2);
    expect(state['failure'], 'cancelled');
    expect(state['ready'], false);
    expect(owner.retainedBytes, 0);
  });

  for (final mode in ['headers', 'body', 'cancel-body']) {
    test('real relay stop correlates $mode with an opaque published media identity', () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final release = Completer<void>();
      final seen = Completer<void>();
      final jobs = <Future<void>>{};
      final subscription = origin.listen((request) {
        late Future<void> work;
        work = () async {
          try {
            if (request.uri.path == '/root.m3u8') {
              request.response.write(
                '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:10\n'
                '#EXTINF:2,\npart.ts?token=PRIVATE\n#EXT-X-ENDLIST\n',
              );
            } else {
              request.response.contentLength = 4;
              request.response.bufferOutput = false;
              if (mode != 'headers') {
                request.response.add([1, 2]);
                await request.response.flush();
              }
              seen.complete();
              await release.future;
              request.response.add(mode == 'headers' ? [1, 2, 3, 4] : [3, 4]);
            }
            await request.response.close();
          } on Object {
            // This fixture's socket can be closed by the cancellation control.
          }
        }().whenComplete(() => jobs.remove(work));
        jobs.add(work);
      });
      final observer = HlsRelayDiagnostics();
      final relay = (await FFmpegHlsInputRelay.startForArguments(
        ['-i', 'http://127.0.0.1:${origin.port}/root.m3u8'],
        drainOnStop: true,
        enablePrefetch: true,
        diagnostics: observer,
        findProxy: (_) => 'DIRECT',
      ))!;
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        final request = await client.getUrl(relay.inputUri);
        final manifest = await (await request.close()).transform(utf8.decoder).join();
        final local = Uri.parse(manifest.split('\n').firstWhere((line) => line.startsWith('http')));
        await seen.future.timeout(const Duration(seconds: 3));
        if (mode != 'headers') {
          // ignore: invalid_use_of_visible_for_testing_member
          await until(() => relay.prefetchBytes == 2);
        }
        await relay.finish();
        final first = (observer.snapshot()['prefetchDownloadCheckpoints'] as List).single as Map;
        final resource = (first['resources'] as List).single as Map;
        final ticket = resource['ticket'] as Map;
        expect(resource['resourceId'], local.pathSegments.last.split('.').first);
        expect(resource['sequence'], 10);
        expect(resource['admitted'], true);
        expect(ticket['phase'], mode == 'headers' ? 'loading' : 'body');
        expect(ticket['receivedBytes'], mode == 'headers' ? 0 : 2);
        if (mode == 'cancel-body') {
          await relay.close();
        } else {
          release.complete();
          await until(() => (observer.snapshot()['prefetchDownloadCheckpoints'] as List).length == 2);
          expect(relay.inputTailDiscarded, false);
        }
        final checkpoints = observer.snapshot()['prefetchDownloadCheckpoints'] as List;
        final terminal = (checkpoints.last['resources'] as List).single['ticket'] as Map;
        expect(terminal['failure'], mode == 'cancel-body' ? 'cancelled' : null);
        expect(terminal['phase'], mode == 'cancel-body' ? 'body' : 'ready');
        expect(jsonEncode(checkpoints), isNot(contains('PRIVATE')));
        expect(jsonEncode(checkpoints), isNot(contains('http:')));
        (checkpoints.first as Map)['resources'] = [];
        expect(((observer.snapshot()['prefetchDownloadCheckpoints'] as List).first['resources'] as List), hasLength(1));
        await relay.finish();
        expect((observer.snapshot()['prefetchDownloadCheckpoints'] as List), hasLength(2));
      } finally {
        if (!release.isCompleted) release.complete();
        client.close(force: true);
        await relay.close();
        await origin.close(force: true);
        await subscription.cancel();
        await Future.wait(jobs.toList());
      }
    });
  }
}

Future<void> until(bool Function() predicate) async {
  final clock = Stopwatch()..start();
  while (!predicate()) {
    if (clock.elapsed > const Duration(seconds: 3)) throw StateError('Expected prefetch phase absent');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
