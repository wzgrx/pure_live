import 'dart:async';

import 'package:floating/floating.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PiP observation preserves state through errors and restarts after reset', (tester) async {
    final floating = Floating()..reset();
    const channel = MethodChannel('floating');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var fail = false;
    var enabled = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pipAvailable') return true;
      if (call.method == 'inPipAlready') {
        if (fail) throw PlatformException(code: 'fixture-detached');
        return enabled;
      }
      return null;
    });
    final received = <PiPStatus>[];
    final subscription = floating.pipStatusStream.listen(received.add);
    await tester.pump(const Duration(milliseconds: 100));
    expect(received, [PiPStatus.enabled]);
    fail = true;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(received, [PiPStatus.enabled]);
    fail = false;
    enabled = false;
    await tester.pump(const Duration(milliseconds: 100));
    expect(received, [PiPStatus.enabled, PiPStatus.disabled]);
    unawaited(subscription.cancel());
    await tester.pump();
    floating.reset();
    final afterReset = <PiPStatus>[];
    final restarted = floating.pipStatusStream.listen(afterReset.add);
    await tester.pump(const Duration(milliseconds: 100));
    expect(afterReset, [PiPStatus.disabled]);
    unawaited(restarted.cancel());
    await tester.pump();
    floating.reset();
    messenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('PiP polling belongs to listeners and rejects retired replies', (tester) async {
    final floating = Floating()..reset();
    const channel = MethodChannel('floating');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var calls = 0;
    var blocked = false;
    final pending = <Completer<bool>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'pipAvailable') return true;
      if (call.method == 'inPipAlready') {
        calls++;
        if (blocked) {
          final reply = Completer<bool>();
          pending.add(reply);
          return reply.future;
        }
        return false;
      }
      return null;
    });
    addTearDown(() {
      floating.reset();
      messenger.setMockMethodCallHandler(channel, null);
    });
    Future<void> tick([int count = 1]) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final stream = floating.pipStatusStream;
    await tick(2);
    final getterOnlyCalls = calls;
    final first = stream.listen((_) {});
    final second = stream.listen((_) {});
    await tick();
    unawaited(first.cancel());
    await tester.pump();
    final beforeRemainingListener = calls;
    await tick();
    final remainingListenerPolled = calls > beforeRemainingListener;
    unawaited(second.cancel());
    await tester.pump();
    final beforeIdle = calls;
    await tick(2);
    final idleCalls = calls - beforeIdle;

    blocked = true;
    final retired = stream.listen((_) {});
    await tick(3);
    final concurrentRequests = pending.length;
    unawaited(retired.cancel());
    await tester.pump();
    final received = <PiPStatus>[];
    final current = stream.listen(received.add);
    for (final reply in pending) {
      reply.complete(true);
    }
    await tester.pump();
    final staleEnabled = received.contains(PiPStatus.enabled);
    blocked = false;
    await tick(2);
    final resumed = received.contains(PiPStatus.disabled);
    unawaited(current.cancel());
    await tester.pump();
    floating.reset();

    expect(
      {
        'getterOnlyCalls': getterOnlyCalls,
        'remainingListenerPolled': remainingListenerPolled,
        'idleCalls': idleCalls,
        'concurrentRequests': concurrentRequests,
        'staleEnabled': staleEnabled,
        'resumed': resumed,
      },
      {
        'getterOnlyCalls': 0,
        'remainingListenerPolled': true,
        'idleCalls': 0,
        'concurrentRequests': 1,
        'staleEnabled': false,
        'resumed': true,
      },
    );
  });
}
