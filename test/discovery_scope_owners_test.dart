import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_quality_discovery.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/niconico/niconico_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/modules/multiview/multiview_controller.dart';
import 'package:pure_live/modules/multiview/models/multiview_models.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

import 'niconico_quality_catalog_test.dart' as catalog;
import 'niconico_hls_input_test.dart' as fixture;

LiveRoom room() => LiveRoom(roomId: 'lv100', platform: 'niconico', liveStatus: LiveStatus.live);
Future<void> tick() => Future<void>.delayed(Duration.zero);

class _Discovery {
  final h = catalog.Harness();
  final started = Completer<CancelToken>();
  final seat = fixture.Seat()..closeGate = Completer<void>();
  _Discovery() {
    h.factory = (_, _, _) async => seat;
    h.reader = (_, _, token, _) async {
      started.complete(token);
      await token.whenCancel;
      throw StateError('cancelled read');
    };
  }
  NiconicoSite get site => NiconicoSite(api: h.api, catalog: h.catalog());
  void release() {
    if (!seat.closeGate!.isCompleted) seat.closeGate!.complete();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final action in ['remove', 'dispose', 'close', 'shrink']) {
    test('multiview $action cancels production discovery and retains its cleanup fence', () async {
      final d = _Discovery();
      final controller = MultiviewController(
        siteFor: (_) => Site(id: 'niconico', name: 'niconico', logo: '', liveSite: d.site),
        playerFactory: ({required renderWidth, required renderHeight}) =>
            throw StateError('native allocation after cancellation'),
        pauseGlobalPlayback: () async {},
      );
      final index = action == 'shrink' ? 3 : 0;
      final pending = controller.assignRoom(index, room());
      final token = await d.started.future;
      Future<void>? operation;
      try {
        switch (action) {
          case 'remove':
            controller.removeCell(index);
          case 'dispose':
            operation = controller.disposeAll();
          case 'close':
            controller.onClose();
          case 'shrink':
            operation = controller.setLayout(MultiviewLayout.dual);
        }
        await d.seat.closeStarted.future;
        expect(token.isCancelled, true);
        var finished = false;
        final cleanup = controller.disposeAll().then((_) => finished = true);
        await tick();
        expect(finished, false);
        d.release();
        await cleanup;
        await operation;
        await pending;
        expect(d.seat.closes, 1);
        expect(d.seat.grant.retainedCookieCount, 0);
        expect(controller.cells.every((cell) => cell.status == MultiviewCellStatus.empty), true);
        if (action == 'close') {
          await controller.assignRoom(0, room());
          expect(d.h.reads, 1);
        }
      } finally {
        d.release();
        await pending;
        await operation;
        await controller.disposeAll();
      }
    });
  }
  test('same-slot replacement and another cell have independent discovery tokens', () async {
    final ds = [_Discovery(), _Discovery(), _Discovery()];
    var next = 0;
    final controller = MultiviewController(
      siteFor: (_) => Site(id: 'niconico', name: 'niconico', logo: '', liveSite: ds[next++].site),
      playerFactory: ({required renderWidth, required renderHeight}) =>
          throw StateError('unexpected native allocation'),
      pauseGlobalPlayback: () async {},
    );
    final first = controller.assignRoom(0, room());
    final a = await ds[0].started.future;
    final other = controller.assignRoom(1, room());
    final b = await ds[1].started.future;
    final replacement = controller.assignRoom(0, room());
    final c = await ds[2].started.future;
    try {
      expect(a.isCancelled, true);
      expect(b.isCancelled, false);
      expect(c.isCancelled, false);
      controller.removeCell(0);
      await tick();
      expect(c.isCancelled, true);
      expect(b.isCancelled, false);
    } finally {
      final cleanup = controller.disposeAll();
      for (final d in ds) {
        d.release();
      }
      await Future.wait([first, other, replacement, cleanup]);
    }
    expect(ds.map((d) => d.seat.closes), [1, 1, 1]);
  });
  test('layout shrink cancels all removed discoveries before any gated cleanup settles', () async {
    final ds = [_Discovery(), _Discovery()];
    var next = 0;
    final controller = MultiviewController(
      siteFor: (_) => Site(id: 'niconico', name: 'niconico', logo: '', liveSite: ds[next++].site),
      playerFactory: ({required renderWidth, required renderHeight}) =>
          throw StateError('unexpected native allocation'),
      pauseGlobalPlayback: () async {},
    );
    final a = controller.assignRoom(2, room());
    await ds[0].started.future;
    final b = controller.assignRoom(3, room());
    await ds[1].started.future;
    final shrinking = controller.setLayout(MultiviewLayout.dual);
    try {
      await Future.wait(ds.map((d) => d.seat.closeStarted.future)).timeout(const Duration(seconds: 2));
      for (final d in ds) {
        expect((await d.started.future).isCancelled, true);
      }
    } finally {
      for (final d in ds) {
        d.release();
      }
      await Future.wait([a, b, shrinking]);
      await controller.disposeAll();
    }
    expect(controller.cells.length, 2);
  });
  test('resized slot rejects pre-shrink legacy resolution after index reuse', () async {
    final replies = <Completer<MultiviewStreamSource>>[];
    var nativeAllocations = 0;
    final controller = MultiviewController(
      streamResolver: (_, {required preferLowest}) {
        final reply = Completer<MultiviewStreamSource>();
        replies.add(reply);
        return reply.future;
      },
      playerFactory: ({required renderWidth, required renderHeight}) {
        nativeAllocations++;
        throw StateError('unexpected stale native allocation');
      },
      pauseGlobalPlayback: () async {},
    );
    final old = controller.assignRoom(3, room());
    await tick();
    await controller.setLayout(MultiviewLayout.dual);
    await controller.setLayout(MultiviewLayout.quad);
    final replacement = controller.assignRoom(
      3,
      LiveRoom(roomId: 'lv200', platform: 'niconico', liveStatus: LiveStatus.live),
    );
    await tick();
    try {
      replies.first.complete(const MultiviewStreamSource(url: 'https://fixture.invalid/old.m3u8', headers: {}));
      await old;
      expect(nativeAllocations, 0);
      expect(controller.cells[3].room!.roomId, 'lv200');
      expect(controller.cells[3].status, MultiviewCellStatus.resolving);
    } finally {
      controller.removeCell(3);
      if (!replies.first.isCompleted) replies.first.completeError(StateError('old cleanup'));
      replies.last.completeError(StateError('replacement cleanup'));
      await Future.wait([old, replacement]);
      await controller.disposeAll();
    }
  });
  test('closed scope fences late metadata before any quality allocation', () async {
    final site = _Metadata();
    final scope = LiveQualityDiscoveryScope();
    final resolver = StreamResolverService(siteResolver: (_) => site);
    final pending = expectLater(
      resolver.resolveStream(roomId: 'lv100', platform: 'niconico', preferredQuality: 'highest', discoveryScope: scope),
      throwsA(isA<DioException>()),
    );
    await scope.close();
    site.reply.complete(room());
    await pending;
    expect(site.qualities, 0);
  });
  test('actual recorder resolver propagates cancel and releases production catalog seat', () async {
    final d = _Discovery();
    final scope = LiveQualityDiscoveryScope();
    final resolver = StreamResolverService(siteResolver: (_) => d.site);
    final pending = expectLater(
      resolver.resolveStream(roomId: 'lv100', platform: 'niconico', preferredQuality: 'highest', discoveryScope: scope),
      throwsA(isA<DioException>()),
    );
    final token = await d.started.future;
    var closed = false;
    final close = scope.close().then((_) => closed = true);
    try {
      await d.seat.closeStarted.future;
      expect(token.isCancelled, true);
      expect(closed, false);
    } finally {
      d.release();
      await Future.wait([pending, close]);
    }
    expect(d.seat.closes, 1);
    expect(d.seat.grant.retainedCookieCount, 0);
  });
  test('scope close is idempotent and future requests allocate no transport', () async {
    final d = _Discovery();
    final scope = LiveQualityDiscoveryScope();
    expect(scope.close(), same(scope.close()));
    await scope.close();
    await expectLater(scope.discover(d.site, room()), throwsA(isA<DioException>()));
    expect(d.h.requests, 0);
  });
}

class _Metadata extends LiveSite {
  final reply = Completer<LiveRoom>();
  int qualities = 0;
  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) => reply.future;
  @override
  Future<List<Never>> getPlayQualites({required LiveRoom detail}) async {
    qualities++;
    return [];
  }
}
