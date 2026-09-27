import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';

void main() {
  test('F-FAV-04: the cover period follows the switch and the interval', () async {
    final store = await LiveStore.inMemory();
    addTearDown(store.close);
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final keep = container.listen(coverPeriodProvider, (_, _) {});
    addTearDown(keep.close);
    expect(container.read(coverPeriodProvider), isNull, reason: 'off by default, as in 3.x');

    await store.settings.set(Settings.autoRefreshCovers, true);
    await pumpEventQueue();
    const half = Duration(minutes: 30);
    final period = container.read(coverPeriodProvider);
    expect(period, DateTime.now().millisecondsSinceEpoch ~/ half.inMilliseconds);

    await store.settings.set(Settings.coverRefreshInterval, 360);
    await pumpEventQueue();
    expect(
      container.read(coverPeriodProvider),
      DateTime.now().millisecondsSinceEpoch ~/ const Duration(hours: 6).inMilliseconds,
    );
  });
}
