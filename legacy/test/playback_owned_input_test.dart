import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/player/core/playback_source_transport.dart';

class Lease {
  Lease(int id) {
    input = PlaybackInputLease(Uri.parse('http://127.0.0.1:18000/$id/root.m3u8'), close, isUsable: () => alive);
  }
  late final PlaybackInputLease input;
  int closes = 0;
  bool alive = true;
  final closing = Completer<void>();
  Completer<void>? closeGate;
  Object? closeError;
  Future<void> close() async {
    closes++;
    closing.complete();
    await closeGate?.future;
    if (closeError != null) throw closeError!;
  }
}

Future<void> open(PlaybackSourceTransport owner, PlaybackOwnedInputFactory factory, {PlaybackNativeOpen? native}) =>
    owner.openOwned(
      createInput: factory,
      nativeOpen:
          native ??
          (uri, choices, headers, private) async {
            expect(Uri.parse(uri).host, '127.0.0.1');
            expect(choices, [uri]);
            expect(headers, isEmpty);
            expect(private, true);
          },
    );

void main() {
  test('owned input opens without any placeholder source URL and remains live until close', () async {
    final owner = PlaybackSourceTransport();
    final lease = Lease(1);
    late CancelToken token;
    await open(owner, (cancel) async {
      token = cancel;
      return lease.input;
    });
    expect(token.isCancelled, false);
    expect(lease.input.isUsable, true);
    await owner.close();
    expect(lease.input.isUsable, false);
    expect(lease.closes, 1);
  });
  test('close cancels acquisition and joins its cleanup but not a native open', () async {
    final owner = PlaybackSourceTransport();
    final cleanup = Completer<void>();
    late CancelToken token;
    final result = expectLater(
      open(owner, (cancel) async {
        token = cancel;
        final error = await cancel.whenCancel;
        await cleanup.future;
        throw error;
      }),
      throwsA(isA<DioException>().having((e) => e.type, 'kind', DioExceptionType.cancel)),
    );
    var closed = false;
    final closing = owner.close().then((_) => closed = true);
    await token.whenCancel;
    expect(closed, false);
    cleanup.complete();
    await result;
    await closing;
    expect(closed, true);
  });
  test('late allocation is closed once; teardown waits for its real cleanup', () async {
    final owner = PlaybackSourceTransport();
    final created = Completer<PlaybackInputLease>();
    final lease = Lease(1)..closeGate = Completer<void>();
    final result = expectLater(
      open(owner, (_) => created.future, native: (_, _, _, _) async => fail('late native')),
      throwsStateError,
    );
    var closed = false;
    final closing = owner.close().then((_) => closed = true);
    created.complete(lease.input);
    await lease.closing.future;
    expect(closed, false);
    expect(lease.input.isUsable, false);
    lease.closeGate!.complete();
    await result;
    await closing;
    expect(lease.closes, 1);
  });
  test('canceling replacement acquisition retains the committed input', () async {
    final owner = PlaybackSourceTransport();
    final active = Lease(1);
    await open(owner, (_) async => active.input);
    final result = expectLater(
      open(owner, (cancel) async => throw await cancel.whenCancel),
      throwsA(isA<DioException>()),
    );
    await owner.cancelPending();
    await result;
    expect(active.closes, 0);
    await owner.close();
    expect(active.closes, 1);
  });
  test('newer source cancels old creation before acquiring its own input', () async {
    final owner = PlaybackSourceTransport();
    final cleanup = Completer<void>();
    late CancelToken oldToken;
    final old = expectLater(
      open(owner, (cancel) async {
        oldToken = cancel;
        final error = await cancel.whenCancel;
        await cleanup.future;
        throw error;
      }),
      throwsA(isA<DioException>()),
    );
    var created = false;
    final lease = Lease(2);
    final next = open(owner, (_) async {
      created = true;
      return lease.input;
    });
    await oldToken.whenCancel;
    expect(created, false);
    cleanup.complete();
    await old;
    await next;
    expect(created, true);
    await owner.close();
  });
  test('intermediate source intent is dropped while prior creation cleanup is pending', () async {
    final owner = PlaybackSourceTransport();
    final cleanup = Completer<void>();
    final old = expectLater(
      open(owner, (cancel) async {
        final error = await cancel.whenCancel;
        await cleanup.future;
        throw error;
      }),
      throwsA(isA<DioException>()),
    );
    var skippedFactories = 0;
    final skipped = expectLater(
      open(owner, (_) async {
        skippedFactories++;
        throw StateError('skipped factory must not run');
      }, native: (_, _, _, _) async => fail('skipped native')),
      throwsStateError,
    );
    final lease = Lease(3);
    final latest = open(owner, (_) async => lease.input);
    cleanup.complete();
    await old;
    await skipped;
    await latest;
    expect(skippedFactories, 0);
    expect(lease.closes, 0);
    await owner.close();
  });
  test('new source retires pending native input without awaiting its late native callback', () async {
    final owner = PlaybackSourceTransport();
    final oldLease = Lease(1);
    final entered = Completer<void>();
    final native = Completer<void>();
    final old = expectLater(
      open(
        owner,
        (_) async => oldLease.input,
        native: (_, _, _, _) async {
          entered.complete();
          await native.future;
        },
      ),
      throwsStateError,
    );
    await entered.future;
    final next = Lease(2);
    await open(owner, (_) async => next.input);
    expect(oldLease.closes, 1);
    expect(next.closes, 0);
    native.complete();
    await old;
    expect(next.closes, 0);
    await owner.close();
  });
  for (final when in ['factory', 'native']) {
    test('ended input at $when never commits or retires the retained input', () async {
      final owner = PlaybackSourceTransport();
      final active = Lease(1);
      await open(owner, (_) async => active.input);
      final candidate = Lease(2);
      var nativeCalls = 0;
      await expectLater(
        open(
          owner,
          (_) async {
            if (when == 'factory') candidate.alive = false;
            return candidate.input;
          },
          native: (_, _, _, _) async {
            nativeCalls++;
            candidate.alive = false;
          },
        ),
        throwsStateError,
      );
      expect(nativeCalls, when == 'factory' ? 0 : 1);
      expect(candidate.closes, 1);
      expect(active.closes, 0);
      await owner.close();
    });
  }
  test('native rejection closes candidate but preserves the prior input', () async {
    final owner = PlaybackSourceTransport();
    final active = Lease(1);
    final candidate = Lease(2);
    await open(owner, (_) async => active.input);
    await expectLater(
      open(owner, (_) async => candidate.input, native: (_, _, _, _) async => throw StateError('native failed')),
      throwsStateError,
    );
    expect(candidate.closes, 1);
    expect(active.closes, 0);
    await owner.close();
  });
  for (final stage in ['factory', 'late cleanup', 'foreign cancellation']) {
    test('$stage failure is reported by both opening and joined teardown', () async {
      final owner = PlaybackSourceTransport();
      final active = Lease(1);
      await open(owner, (_) async => active.input);
      final factory = Completer<PlaybackInputLease>();
      final Object error = stage == 'foreign cancellation' ? (CancelToken()..cancel()).cancelError! : StateError(stage);
      final failed = expectLater(open(owner, (_) => factory.future), throwsA(same(error)));
      final closing = expectLater(owner.close(), throwsA(same(error)));
      if (stage == 'late cleanup') {
        factory.complete((Lease(2)..closeError = error).input);
      } else {
        factory.completeError(error);
      }
      await failed;
      await closing;
      expect(active.closes, 1);
    });
  }
  test('ordinary factory failure has no unhandled cleanup future or retained input', () async {
    final owner = PlaybackSourceTransport();
    await expectLater(open(owner, (_) async => throw StateError('startup')), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    await owner.close();
  });
  test('direct source replacement retires an owned lease and preserves direct headers', () async {
    final owner = PlaybackSourceTransport();
    final lease = Lease(1);
    await open(owner, (_) async => lease.input);
    const uri = 'https://media.example/direct.m3u8';
    await owner.open(
      url: uri,
      urls: const [uri],
      headers: const {'Cookie': 'fixture'},
      policy: null,
      nativeOpen: (source, urls, headers, private) async {
        expect(source, uri);
        expect(headers, {'Cookie': 'fixture'});
        expect(private, false);
        expect(lease.closes, 0);
      },
    );
    expect(lease.closes, 1);
    await owner.close();
  });
  test('close joins stale cleanup that a superseding open already started', () async {
    final owner = PlaybackSourceTransport();
    final lease = Lease(1)..closeGate = Completer<void>();
    final entered = Completer<void>();
    final native = Completer<void>();
    final old = expectLater(
      open(
        owner,
        (_) async => lease.input,
        native: (_, _, _, _) async {
          entered.complete();
          await native.future;
        },
      ),
      throwsStateError,
    );
    await entered.future;
    var laterFactories = 0;
    final next = expectLater(
      open(owner, (_) async {
        laterFactories++;
        return Lease(2).input;
      }),
      throwsStateError,
    );
    await lease.closing.future;
    var closed = false;
    final closing = owner.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, false);
    lease.closeGate!.complete();
    await closing;
    await next;
    native.complete();
    await old;
    expect(laterFactories, 0);
    expect(lease.closes, 1);
  });
}
