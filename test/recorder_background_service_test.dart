import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/recorder/services/recorder_background_service.dart';

void main() {
  test('multiple identity owners share one service until the last release', () async {
    final calls = <bool>[];
    final service = RecorderBackgroundService(supported: true, apply: (value) async => calls.add(value));
    final first = Object();
    final second = Object();
    await service.acquire(first);
    await service.acquire(second);
    await service.release(first);
    await service.release(first);
    expect(calls, [true]);
    expect(service.ownerCount, 1);
    await service.release(second);
    expect(calls, [true, false]);
    await service.dispose();
  });

  test('cancel while native start is pending drains the final false intent', () async {
    final gate = Completer<void>();
    final calls = <bool>[];
    final service = RecorderBackgroundService(
      supported: true,
      apply: (value) async {
        calls.add(value);
        if (value) await gate.future;
      },
    );
    final owner = Object();
    final starting = service.acquire(owner);
    final stopping = service.release(owner);
    gate.complete();
    await Future.wait([starting, stopping]);
    expect(calls, [true, false]);
    expect(service.ownerCount, 0);
    await service.dispose();
  });

  test('start failure rolls back and only an explicit user retry restarts', () async {
    var reject = true;
    final calls = <bool>[];
    final service = RecorderBackgroundService(
      supported: true,
      apply: (value) async {
        calls.add(value);
        if (value && reject) throw StateError('denied');
      },
    );
    await expectLater(service.acquire(Object()), throwsA(isA<RecorderBackgroundException>()));
    expect(service.ownerCount, 0);
    reject = false;
    await expectLater(service.acquire(Object()), throwsA(isA<RecorderBackgroundException>()));
    expect(calls.where((value) => value), hasLength(1));
    service.allowUserRetry();
    final owner = Object();
    await service.acquire(owner);
    expect(calls.where((value) => value), hasLength(2));
    await service.release(owner);
    await service.dispose();
  });

  test('interruption retains cleanup without trying to restart native service', () async {
    final calls = <bool>[];
    final service = RecorderBackgroundService(supported: true, apply: (value) async => calls.add(value));
    final owner = Object();
    final cleanup = Object();
    await service.acquire(owner);
    var notifications = 0;
    service.addInterruptionListener((reason) async {
      notifications++;
      expect(reason, 'timeout');
      service.retainForCleanup(cleanup);
      await service.release(owner);
      expect(calls, [true]);
      await service.release(cleanup);
    });
    await service.handleInterruption('timeout');
    await service.handleInterruption('timeout');
    expect(calls, [true, false]);
    expect(notifications, 1);
    expect(service.ownerCount, 0);
    await service.dispose();
  });

  test('failed native stop invalidates cached active state before another start', () async {
    final calls = <bool>[];
    var rejectStop = true;
    final service = RecorderBackgroundService(
      supported: true,
      apply: (active) async {
        calls.add(active);
        if (!active && rejectStop) throw StateError('stop timeout after native cleanup');
      },
    );
    final first = Object();
    await service.acquire(first);
    await expectLater(service.release(first), throwsA(isA<RecorderBackgroundException>()));
    rejectStop = false;
    final second = Object();
    await service.acquire(second);
    expect(calls, [true, false, true]);
    await service.release(second);
    await service.dispose();
  });
  test('idle engine release follows the complete false transition', () async {
    final stopGate = Completer<void>();
    final calls = <String>[];
    final service = RecorderBackgroundService(
      supported: true,
      apply: (active) async {
        calls.add('$active');
        if (!active) await stopGate.future;
      },
      releaseIdle: () async => calls.add('releaseIdle'),
    );
    final owner = Object();
    await service.acquire(owner);
    final stopping = service.release(owner);
    expect(calls, ['true', 'false']);
    stopGate.complete();
    await stopping;
    expect(calls, ['true', 'false', 'releaseIdle']);
    await service.dispose();
  });

  test('new owner during false retains engine through queued true', () async {
    final stopGate = Completer<void>();
    final calls = <String>[];
    final service = RecorderBackgroundService(
      supported: true,
      apply: (active) async {
        calls.add('$active');
        if (!active) await stopGate.future;
      },
      releaseIdle: () async => calls.add('releaseIdle'),
    );
    final oldOwner = Object();
    final newOwner = Object();
    await service.acquire(oldOwner);
    final stopping = service.release(oldOwner);
    final starting = service.acquire(newOwner);
    expect(calls, ['true', 'false']);
    stopGate.complete();
    await Future.wait([stopping, starting]);
    expect(calls, ['true', 'false', 'true']);
    expect(service.ownerCount, 1);
    await service.release(newOwner);
    expect(calls, ['true', 'false', 'true', 'false', 'releaseIdle']);
    await service.dispose();
  });

  test('cancelled replacement during false still confirms final idle', () async {
    final stopGate = Completer<void>();
    var idleReleases = 0;
    final service = RecorderBackgroundService(
      supported: true,
      apply: (active) async {
        if (!active) await stopGate.future;
      },
      releaseIdle: () async {
        idleReleases++;
      },
    );
    final first = Object();
    final second = Object();
    await service.acquire(first);
    final stoppingFirst = service.release(first);
    final startingSecond = service.acquire(second);
    final stoppingSecond = service.release(second);
    stopGate.complete();
    await Future.wait([stoppingFirst, startingSecond, stoppingSecond]);
    expect(service.ownerCount, 0);
    expect(idleReleases, 1);
    await service.dispose();
  });
  test('unsupported platforms do not invoke Android transport', () async {
    final service = RecorderBackgroundService(supported: false, apply: (_) async => fail('Android called'));
    final owner = Object();
    await service.acquire(owner);
    await service.release(owner);
    await service.dispose();
  });
}
