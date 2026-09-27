import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/clock.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/alert_notifier.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';

import '../alerts/fake_notifier.dart';

final _started = DateTime.utc(2026, 9, 28, 11);

/// Room details by id: `gone` does not exist, `bad` fails like the network,
/// others are live since [_started]; [gate] holds every answer back.
final class _Site implements RoomSource {
  new(this.platform);

  final String platform;
  final requests = <String>[];
  Completer<void>? gate;

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    requests.add(ref.roomId);
    await gate?.future;
    return switch (ref.roomId) {
      'gone' => throw NotFound(platform),
      'bad' => throw NetworkFailure(platform, 'offline'),
      final id => RoomDetail(
        card: RoomCard(ref: ref, title: '标题$id', anchorName: '主播$id', state: LiveState.live, liveSince: _started),
        link: Uri.parse('https://example.com/$id'),
      ),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LiveStore store;

  setUp(() async => store = await LiveStore.inMemory());
  tearDown(() => store.close());

  Future<void> follow(String platform, String id) =>
      store.follows.follow(RoomSnapshot(ref: RoomRef(platform, id), anchorName: '主播$id', state: LiveState.offline));

  ProviderContainer container(Map<String, _Site> sites, {DateTime Function()? clock}) {
    final container = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(store),
        sitesProvider.overrideWithValue({for (final MapEntry(:key, :value) in sites.entries) key: PlatformSite(value)}),
        alertNotifierProvider.overrideWithValue(FakeAlertNotifier()),
        if (clock != null) clockProvider.overrideWithValue(clock),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('F-FAV-03, F-FAV-08: failures, missing rooms and other platforms are marked, not guessed', () async {
    for (final (platform, id) in [('douyu', 'a'), ('douyu', 'gone'), ('huya', 'bad'), ('huajiao', '1')]) {
      await follow(platform, id);
    }
    final douyu = _Site('douyu');
    final huya = _Site('huya');
    final c = container({'douyu': douyu, 'huya': huya});

    final result = (await c.read(followRefreshProvider.future))!;
    expect(result.skipped, {'huajiao:1'}, reason: 'no adapter, never requested');
    expect(result.missing, {'douyu:gone'});
    expect(result.failed, {'huya:bad'});
    expect(result.failedPlatforms, {'huya'});
    expect(result.liveSince, {'douyu:a': _started});
    expect(result.checked, 1);
    expect(douyu.requests..sort(), ['a', 'gone']);
    expect((await store.rooms.get(RoomRef('douyu', 'a')))!.lastState, LiveState.live, reason: 'stored in one write');
    expect((await store.rooms.get(RoomRef('huya', 'bad')))!.lastState, LiveState.offline, reason: 'the cache stays');
  });

  test('a refresh asked for while one runs joins it', () async {
    await follow('douyu', 'a');
    final douyu = _Site('douyu')..gate = Completer<void>();
    final c = container({'douyu': douyu});

    final first = c.read(followRefreshProvider.future);
    await pumpEventQueue();
    final joined = c.read(followRefreshProvider.notifier).refresh();
    douyu.gate!.complete();
    expect(await joined, same(await first));
    expect(douyu.requests, ['a'], reason: 'one pass');

    douyu.gate = null;
    final later = c.read(followRefreshProvider.notifier).refresh();
    expect(c.read(followRefreshProvider).isLoading, isTrue, reason: 'the spinner shows');
    expect(c.read(followRefreshProvider).value, isNotNull, reason: 'the last result stays until the new one');
    await later;
    expect(douyu.requests, ['a', 'a']);
  });

  test('a refresh that cannot read the store keeps the last result and stops the spinner', () async {
    final broken = await LiveStore.inMemory();
    await broken.follows.follow(RoomSnapshot(ref: RoomRef('douyu', 'a'), anchorName: '主播a'));
    final c = ProviderContainer(
      overrides: [
        storeProvider.overrideWithValue(broken),
        sitesProvider.overrideWithValue({'douyu': PlatformSite(_Site('douyu'))}),
        alertNotifierProvider.overrideWithValue(FakeAlertNotifier()),
      ],
    );
    addTearDown(c.dispose);
    final first = await c.read(followRefreshProvider.future);
    await broken.close();

    final again = await c.read(followRefreshProvider.notifier).refresh();
    expect(again, same(first));
    final state = c.read(followRefreshProvider);
    expect(state.isLoading, isFalse);
    expect(state.hasError, isTrue);
    expect(state.value, same(first), reason: 'the page keeps what it showed');
  });

  test('F-APP-03: coming back refreshes 450 ms later, only when the last refresh is 15 s old', () async {
    await follow('douyu', 'a');
    final douyu = _Site('douyu');
    var now = DateTime(2026, 9, 28, 12);
    final c = container({'douyu': douyu}, clock: () => now);
    await c.read(followRefreshProvider.future);
    final notifier = c.read(followRefreshProvider.notifier);
    expect(douyu.requests, hasLength(1));

    now = now.add(const Duration(seconds: 10));
    notifier.resumed();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(douyu.requests, hasLength(1), reason: 'refreshed 10 s ago');

    now = now.add(const Duration(seconds: 10));
    notifier.resumed();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(douyu.requests, hasLength(1), reason: 'waits 450 ms');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(douyu.requests, hasLength(2));

    await store.settings.set(Settings.refreshFollowsOnResume, false);
    now = now.add(const Duration(minutes: 5));
    notifier.resumed();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(douyu.requests, hasLength(2), reason: '回到应用时刷新关注 is off');
  });
}
