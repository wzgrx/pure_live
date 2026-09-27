import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/rooms/room_list.dart';

import 'fakes.dart';

void main() {
  ProviderContainer containerWith(FakeSite site) {
    final container = ProviderContainer(
      overrides: [
        sitesProvider.overrideWithValue({site.id: PlatformSite(site)}),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('pages follow the adapter cursor and drop repeated rooms', () async {
    final site = FakeSite('douyu');
    site.pages.addAll([
      Page([site.card('1'), site.card('2')], next: const PageCursor('1')),
      Page([site.card('2'), site.card('3')]),
    ]);
    final container = containerWith(site);
    const query = RecommendedQuery('douyu');
    final subscription = container.listen(roomListProvider(query), (_, _) {});
    addTearDown(subscription.close);

    final first = await container.read(roomListProvider(query).future);
    expect(first.items.map((c) => c.ref.roomId), ['1', '2']);
    expect(first.hasMore, isTrue);

    await container.read(roomListProvider(query).notifier).loadMore();
    final second = container.read(roomListProvider(query)).value!;
    expect(second.items.map((c) => c.ref.roomId), ['1', '2', '3']);
    expect(second.hasMore, isFalse);
    expect(site.cursors, [null, const PageCursor('1')]);

    // At the end, loadMore does nothing.
    await container.read(roomListProvider(query).notifier).loadMore();
    expect(site.cursors, hasLength(2));
  });

  test('a failed next page keeps the loaded rooms and can be retried', () async {
    final site = FakeSite('huya');
    site.pages.addAll([
      Page([site.card('1')], next: const PageCursor('1')),
      Page([site.card('2')]),
    ]);
    final container = containerWith(site);
    const query = SearchQuery('huya', 'lol');
    final subscription = container.listen(roomListProvider(query), (_, _) {});
    addTearDown(subscription.close);
    await container.read(roomListProvider(query).future);

    site.failFirst = true;
    await container.read(roomListProvider(query).notifier).loadMore();
    final failed = container.read(roomListProvider(query)).value!;
    expect(failed.moreError, isA<NetworkFailure>());
    expect(failed.items, hasLength(1));
    expect(failed.hasMore, isTrue);

    await container.read(roomListProvider(query).notifier).loadMore();
    expect(container.read(roomListProvider(query)).value!.items, hasLength(2));
  });
}
