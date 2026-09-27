import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/testing.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/engine.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/multiview/multiview_controller.dart';

import 'fakes.dart';

/// Invariants of spec/modules/multiview.md §11 with fake engines.
void main() {
  late LiveStore store;
  late FakeSite site;
  late List<FakeEngine> engines;
  late ProviderContainer container;

  setUp(() async {
    store = await LiveStore.inMemory();
    site = FakeSite('douyu', offline: {'off'});
    engines = [];
    container =
        ProviderContainer(
            overrides: [
              storeProvider.overrideWithValue(store),
              sitesProvider.overrideWithValue({'douyu': PlatformSite(site)}),
              engineFactoryProvider.overrideWithValue(() {
                final engine = FakeEngine();
                engines.add(engine);
                return engine;
              }),
            ],
          )
          // Keep the auto-dispose controller alive for the test.
          ..listen(multiviewProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await store.close();
  });

  MultiviewController controller() => container.read(multiviewProvider.notifier);
  MultiviewState state() => container.read(multiviewProvider);
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('only the focus cell makes sound; mute-all silences it too (INV-MULTI-01, AUD-3)', () async {
    controller().setLayout(MultiviewLayout.four);
    await controller().assign(0, RoomRef('douyu', '1'));
    await controller().assign(1, RoomRef('douyu', '2'));
    await settle();
    expect(state().audioFocus, 1, reason: 'a newly playing cell takes the focus (AUD-2)');
    expect(engines.map((e) => e.volume), [0, 1]);

    controller().setFocus(0);
    await settle();
    expect(engines.map((e) => e.volume), [1, 0]);

    controller().toggleMuteAll();
    await settle();
    expect(engines.every((e) => e.volume == 0), isTrue);
    controller().setFocus(1);
    await settle();
    expect(state().audioFocus, 1, reason: 'focus still moves while muted');
    expect(engines.every((e) => e.volume == 0), isTrue);
  });

  test('a known offline room creates no decoder and asks for no streams (INV-MULTI-05)', () async {
    await controller().assign(0, RoomRef('douyu', 'off'));
    expect(state().cells[0].status, CellStatus.offline);
    expect(engines, isEmpty);
    expect(site.streamRequests, isEmpty);
  });

  test('a late result never lands in a reassigned cell (INV-MULTI-03)', () async {
    final first = controller().assign(0, RoomRef('douyu', 'slow'));
    final second = controller().assign(0, RoomRef('douyu', 'fast'));
    await Future.wait([first, second]);
    await settle();
    expect(state().cells[0].room, RoomRef('douyu', 'fast'));
    expect(state().cells[0].status, CellStatus.playing);
    final live = engines.where((e) => !e.disposed).length;
    expect(live, 1, reason: 'the superseded session was released');
  });

  test('closing the focus cell moves the focus to the first playing cell and empties at once (CEL-7)', () async {
    controller().setLayout(MultiviewLayout.four);
    await controller().assign(0, RoomRef('douyu', '1'));
    await controller().assign(2, RoomRef('douyu', '3'));
    await settle();
    expect(state().audioFocus, 2);
    controller().close(2);
    expect(state().cells[2].status, CellStatus.empty);
    expect(state().audioFocus, 0);
    await settle();
    expect(engines[1].disposed, isTrue);
  });

  test('shrinking the layout keeps the playing cells and releases the tail (LYT-3)', () async {
    controller().setLayout(MultiviewLayout.four);
    await controller().assign(0, RoomRef('douyu', '1'));
    await controller().assign(3, RoomRef('douyu', '4'));
    await settle();
    final kept = state().cells[0].session;
    controller().setLayout(MultiviewLayout.two);
    await settle();
    expect(state().cells, hasLength(2));
    expect(state().cells[0].session, same(kept), reason: 'no rebuild of the playing cell');
    expect(engines[1].disposed, isTrue);
  });

  test('the pick target moves to the next free cell after an assignment (CEL-4)', () async {
    controller().setLayout(MultiviewLayout.four);
    unawaited(controller().assign(0, RoomRef('douyu', '1')));
    expect(state().target, 1);
    await settle();
  });
}
