import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/hls_prefetch_pool.dart';

HlsPrefetchPool memoryPool({int entries = 8, int concurrent = 6, int readers = 8, int bytes = 1024}) => HlsPrefetchPool(
  createDirectory: () => throw StateError('Unexpected disk'),
  maximumEntries: entries,
  maximumConcurrent: concurrent,
  maximumReaders: readers,
  maximumBytes: bytes,
  maximumBodyBytes: bytes,
);
Future<HlsPrefetchResponse> value(HlsPrefetchCancellation _) async =>
    HlsPrefetchResponse(Stream.value([1, 2, 3]), expectedLength: 3);

void main() {
  test('parallel downloads are bounded and identical identities coalesce', () async {
    final pool = memoryPool(entries: 3, concurrent: 2);
    final gates = List.generate(3, (_) => Completer<HlsPrefetchResponse>());
    final started = <int>[];
    final tickets = [
      for (var i = 0; i < 3; i++)
        pool.prefetch('$i', (cancel) {
          started.add(i);
          cancel.onCancel(() {
            if (!gates[i].isCompleted) gates[i].completeError(StateError('Cancelled fixture'));
          });
          return gates[i].future;
        })!,
    ];
    try {
      expect(started, [0, 1]);
      expect(pool.activeDownloads, 2);
      expect(identical(pool.prefetch('0', (_) => throw StateError('Duplicate fetch')), tickets[0]), true);
      expect(pool.prefetch('overflow', value), isNull);
      gates[0].complete(await value(HlsPrefetchCancellation()));
      expect(await tickets[0].ready, true);
      // Completion starts the next queued request without exceeding the cap.
      await Future<void>.delayed(Duration.zero);
      expect(started, [0, 1, 2]);
      expect(pool.activeDownloads, 2);
    } finally {
      await pool.close();
    }
    expect(pool.ownedEntries, 0);
    expect(pool.retainedBytes, 0);
  });
  test('queued retirement never starts its loader and close is idempotent', () async {
    final pool = memoryPool(entries: 2, concurrent: 1);
    final gate = Completer<HlsPrefetchResponse>();
    final first = pool.prefetch('first', (cancel) {
      cancel.onCancel(() => gate.completeError(StateError('Fixture cancelled')));
      return gate.future;
    })!;
    final second = pool.prefetch('second', (_) => throw StateError('Queued work started'))!;
    await pool.evict('second');
    expect(await second.ready, false);
    expect(second.failure, HlsPrefetchFailure.cancelled);
    await pool.close();
    await pool.close();
    expect(await first.ready, false);
    expect(pool.activeDownloads, 0);
    expect(() => pool.prefetch('later', value), throwsStateError);
  });
  test('whole bodies are invisible until seal, then replay to bounded readers', () async {
    final pool = memoryPool(readers: 2);
    final stream = StreamController<List<int>>();
    final ticket = pool.prefetch('body', (_) async => HlsPrefetchResponse(stream.stream, expectedLength: 3))!;
    stream.add([1]);
    await Future<void>.delayed(Duration.zero);
    expect(pool.acquire('body'), isNull);
    stream.add([2, 3]);
    await stream.close();
    expect(await ticket.ready, true);
    final a = pool.acquire('body')!;
    final b = pool.acquire('body')!;
    expect(pool.acquire('body'), isNull);
    try {
      final first = _MutatingCollector();
      await a.writeTo(first);
      expect(first.bytes.first, 99);
      final second = _Collector();
      await b.writeTo(second);
      expect(second.bytes, [1, 2, 3]);
      expect(pool.retainedBytes, 3);
    } finally {
      await a.release();
      await b.release();
      await pool.close();
    }
    expect(pool.activeReaders, 0);
  });
  test('aggregate bytes include completed bodies and failed reservations are released', () async {
    final pool = memoryPool(bytes: 5);
    final first = pool.prefetch('first', value)!;
    expect(await first.ready, true);
    final second = pool.prefetch('second', value)!;
    expect(await second.ready, false);
    expect(second.failure, HlsPrefetchFailure.capacity);
    await pool.close();
    expect(pool.retainedBytes, 0);
    expect(pool.ownedEntries, 0);
  });
  test('truncated and oversized bodies never publish', () async {
    final pool = memoryPool(bytes: 4);
    for (final (key, response, failure) in [
      ('short', HlsPrefetchResponse(Stream.value([1]), expectedLength: 2), HlsPrefetchFailure.download),
      ('large', HlsPrefetchResponse(Stream.value([1, 2, 3, 4, 5])), HlsPrefetchFailure.capacity),
      ('declared', HlsPrefetchResponse(Stream.value([1]), expectedLength: 5), HlsPrefetchFailure.capacity),
    ]) {
      final ticket = pool.prefetch(key, (_) async => response)!;
      expect(await ticket.ready, false);
      expect(ticket.failure, failure);
      expect(pool.acquire(key), isNull);
    }
    await pool.close();
    expect(pool.retainedBytes, 0);
  });
  test('close awaits a pending loader and cancels its late response stream', () async {
    final pool = memoryPool();
    final gate = Completer<HlsPrefetchResponse>();
    var cancelNotified = false;
    var bodyCancelled = false;
    final ticket = pool.prefetch('late', (cancel) {
      cancel.onCancel(() => cancelNotified = true);
      return gate.future;
    })!;
    var closed = false;
    final closing = pool.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(cancelNotified, true);
    expect(closed, false);
    expect(pool.activeDownloads, 1);
    final controller = StreamController<List<int>>(onCancel: () => bodyCancelled = true);
    gate.complete(HlsPrefetchResponse(controller.stream));
    await closing;
    await controller.close();
    expect(bodyCancelled, true);
    expect(await ticket.ready, false);
    expect(pool.ownedEntries, 0);
  });
  test('retiring a leased spool waits for its active writer and frees disk exactly once', () async {
    final root = await Directory.systemTemp.createTemp('purelive-prefetch-');
    final pool = HlsPrefetchPool(createDirectory: () => root.createTemp('owned-'), memoryBytesPerBody: 0);
    HlsPrefetchLease? lease;
    final sink = _BlockingCollector();
    try {
      expect(await pool.prefetch('disk', value)!.ready, true);
      lease = pool.acquire('disk')!;
      final writing = lease.writeTo(sink);
      await sink.entered.future;
      await expectLater(lease.writeTo(_Collector()), throwsStateError);
      var evicted = false;
      final eviction = pool.evict('disk').then((_) => evicted = true);
      var closed = false;
      final closing = pool.close().then((_) => closed = true);
      var released = false;
      final releasing = lease.release().then((_) => released = true);
      await Future<void>.delayed(Duration.zero);
      expect(evicted, false);
      expect(closed, false);
      expect(released, false);
      expect(pool.ownedEntries, 1);
      expect(pool.activeReaders, 1);
      expect(await root.list().isEmpty, false);
      sink.resume.complete();
      await writing;
      await releasing;
      await eviction;
      await closing;
      expect(pool.ownedEntries, 0);
      expect(await root.list().isEmpty, true);
      await expectLater(lease.writeTo(_Collector()), throwsStateError);
      await lease.release();
    } finally {
      if (!sink.resume.isCompleted) sink.resume.complete();
      await lease?.release();
      await pool.close();
      await root.delete();
    }
  });
  test('local writer failure releases its pin without poisoning cached bytes', () async {
    final pool = memoryPool();
    expect(await pool.prefetch('body', value)!.ready, true);
    final lease = pool.acquire('body')!;
    await expectLater(lease.writeTo(_Collector(fail: true)), throwsStateError);
    final good = _Collector();
    await lease.writeTo(good);
    expect(good.bytes, [1, 2, 3]);
    await lease.release();
    await pool.close();
  });
  test('retired old generation consumes capacity until its lease is released', () async {
    final pool = memoryPool(entries: 1, concurrent: 1);
    expect(await pool.prefetch('same', value)!.ready, true);
    final lease = pool.acquire('same')!;
    final retiring = pool.evict('same');
    expect(pool.acquire('same'), isNull);
    expect(pool.prefetch('same', value), isNull);
    await lease.release();
    await retiring;
    final replacement = pool.prefetch('same', value)!;
    expect(await replacement.ready, true);
    await pool.close();
  });
  test('cleanup failure remains charged, cancels queued work and surfaces on close', () async {
    final root = await Directory.systemTemp.createTemp('purelive-prefetch-failure-');
    final keep = File('${root.path}${Platform.pathSeparator}keep');
    final pool = HlsPrefetchPool(createDirectory: () async => root, memoryBytesPerBody: 0, maximumConcurrent: 1);
    try {
      expect(await pool.prefetch('body', value)!.ready, true);
      final gate = Completer<HlsPrefetchResponse>();
      final pending = pool.prefetch('pending', (cancel) {
        cancel.onCancel(() => gate.completeError(StateError('Fixture cancelled')));
        return gate.future;
      })!;
      final queued = pool.prefetch('queued', (_) => throw StateError('Queued loader started'))!;
      await keep.writeAsString('unrelated');
      await expectLater(pool.evict('body'), throwsStateError);
      expect(await pending.ready, false);
      expect(await queued.ready, false);
      expect(pool.retainedBytes, 3);
      expect(() => pool.prefetch('later', value), throwsStateError);
      await expectLater(pool.close(), throwsStateError);
      expect(pool.ownedEntries, 1);
      expect(await keep.readAsString(), 'unrelated');
    } finally {
      if (await keep.exists()) await keep.delete();
      await root.delete();
    }
  });
  test('TCP body cancellation reaches the peer rather than just a result Future', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final sent = Completer<void>();
      final peerClosed = Completer<void>();
      final sockets = <Socket>[];
      final subscription = server.listen((socket) {
        sockets.add(socket);
        var replied = false;
        socket.listen(
          (_) {
            if (replied) return;
            replied = true;
            socket.add(ascii.encode('HTTP/1.1 200 OK\r\nContent-Length: 8\r\n\r\nabc'));
            unawaited(socket.flush().then((_) => sent.complete()));
          },
          onDone: () {
            if (!peerClosed.isCompleted) peerClosed.complete();
          },
          onError: (Object _) {
            if (!peerClosed.isCompleted) peerClosed.complete();
          },
        );
      });
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final pool = memoryPool();
      try {
        final ticket = pool.prefetch('tcp', (cancel) async {
          final request = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/body'));
          final detach = cancel.onCancel(request.abort);
          try {
            final response = await request.close();
            return HlsPrefetchResponse(response, expectedLength: response.contentLength);
          } finally {
            detach();
          }
        })!;
        await sent.future.timeout(const Duration(seconds: 3));
        await pool.close().timeout(const Duration(seconds: 3));
        await peerClosed.future.timeout(const Duration(seconds: 3));
        expect(await ticket.ready, false);
        expect(pool.retainedBytes, 0);
      } finally {
        await pool.close();
        client.close(force: true);
        for (final socket in sockets) {
          socket.destroy();
        }
        await subscription.cancel();
        await server.close();
      }
    }, _RealNetwork());
  });
  test('invalid declared size cancels a body without ever requiring its first byte', () async {
    final pool = memoryPool(bytes: 4);
    var cancelled = false;
    final controller = StreamController<List<int>>(onCancel: () => cancelled = true);
    final ticket = pool.prefetch('oversized', (_) async => HlsPrefetchResponse(controller.stream, expectedLength: 5))!;
    expect(await ticket.ready, false);
    await pool.close();
    expect(cancelled, true);
    expect(ticket.failure, HlsPrefetchFailure.capacity);
    await controller.close();
  });
  test('idle body timeout cancels the real stream and releases its capacity', () async {
    final pool = HlsPrefetchPool(
      createDirectory: () => throw StateError('Unexpected disk'),
      bodyIdleTimeout: const Duration(milliseconds: 300),
    );
    var cancelled = false;
    final controller = StreamController<List<int>>(onCancel: () => cancelled = true);
    final ticket = pool.prefetch('idle', (_) async => HlsPrefetchResponse(controller.stream))!;
    expect(await ticket.ready.timeout(const Duration(seconds: 3)), false);
    expect(ticket.failure, HlsPrefetchFailure.timedOut);
    expect(cancelled, true);
    await pool.close();
    await controller.close();
    expect(pool.retainedBytes, 0);
    expect(pool.ownedEntries, 0);
  });
  test('continuous body trickle shares a total budget rather than resetting forever', () async {
    final pool = HlsPrefetchPool(
      createDirectory: () => throw StateError('Unexpected disk'),
      bodyIdleTimeout: const Duration(milliseconds: 300),
    );
    var cancelled = false;
    var chunks = 0;
    final controller = StreamController<List<int>>(onCancel: () => cancelled = true);
    final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      chunks++;
      if (!cancelled) controller.add([1]);
    });
    final watch = Stopwatch()..start();
    try {
      final ticket = pool.prefetch('trickle', (_) async => HlsPrefetchResponse(controller.stream))!;
      expect(await ticket.ready.timeout(const Duration(seconds: 3)), false);
      expect(ticket.failure, HlsPrefetchFailure.timedOut);
      expect(chunks, greaterThanOrEqualTo(6));
      expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(1000));
      expect(cancelled, true);
    } finally {
      timer.cancel();
      await pool.close();
      await controller.close();
    }
    expect(pool.retainedBytes, 0);
  });
  test('invalid capacity configuration is rejected before allocation', () {
    expect(() => memoryPool(entries: 1, concurrent: 2), throwsArgumentError);
    expect(() => memoryPool(readers: 9), throwsArgumentError);
    expect(() => memoryPool(bytes: 0), throwsArgumentError);
  });
}

class _Collector implements StreamConsumer<List<int>> {
  _Collector({this.fail = false});
  final bool fail;
  final List<int> bytes = [];
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      if (fail) throw StateError('Writer fixture failed');
      bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}
}

class _BlockingCollector extends _Collector {
  final entered = Completer<void>();
  final resume = Completer<void>();
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (!entered.isCompleted) entered.complete();
      await resume.future;
    }
  }
}

class _MutatingCollector extends _Collector {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      chunk[0] = 99;
      bytes.addAll(chunk);
    }
  }
}

class _RealNetwork extends HttpOverrides {}
