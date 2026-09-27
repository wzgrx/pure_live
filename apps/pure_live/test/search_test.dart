import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';
import 'package:pure_live_app/features/search/search_page.dart';
import 'package:pure_live_app/features/search/search_results.dart';

import 'fakes.dart';

RoomCard _card(String platform, String id, {int online = 0, LiveState state = LiveState.live}) => RoomCard(
  ref: RoomRef(platform, id),
  title: '标题$id',
  anchorName: '主播$id',
  state: state,
  audience: Audience(online: online),
);

List<String> _ids(List<RoomCard> cards) => [for (final card in cards) card.ref.roomId];

void main() {
  group('F-SRC-01 order', () {
    // As the platforms answered: each platform's own relevance order.
    final cards = [
      _card('douyu', 'd1', online: 10),
      _card('douyu', 'd2', online: 100),
      _card('douyu', 'd3', online: 1000, state: LiveState.offline),
      _card('huya', 'h1', online: 50),
      _card('huya', 'h2', online: 5),
    ];
    const platforms = ['huya', 'douyu'];

    test('smart keeps each platform relevance and takes the platforms in turn; live first', () {
      expect(_ids(sortSearch(cards, SearchSort.smart, platforms: platforms)), ['h1', 'd1', 'h2', 'd2', 'd3']);
    });

    test('platform, then audience', () {
      expect(_ids(sortSearch(cards, SearchSort.platform, platforms: platforms)), ['h1', 'h2', 'd2', 'd1', 'd3']);
    });

    test('audience, then platform', () {
      expect(_ids(sortSearch(cards, SearchSort.audience, platforms: platforms)), ['d2', 'h1', 'd1', 'h2', 'd3']);
    });
  });

  group('F-SRC-01 综合 paging', () {
    late FakeSite douyu;
    late FakeSite huya;
    late ProviderContainer container;

    setUp(() {
      douyu = FakeSite(
        'douyu',
        pages: [
          Page([_card('douyu', 'd1'), _card('douyu', 'd2')], next: const PageCursor('1')),
          Page([_card('douyu', 'd2'), _card('douyu', 'd3')], next: const PageCursor('2')),
          Page([_card('douyu', 'd3')], next: const PageCursor('3')),
          Page([_card('douyu', 'd1')], next: const PageCursor('4')),
          Page([_card('douyu', 'd9')]),
        ],
      );
      huya = FakeSite(
        'huya',
        pages: [
          Page([_card('huya', 'h1')]),
        ],
      );
      final bilibili = FakeSite('bilibili', failFirst: true);
      container = ProviderContainer(
        overrides: [
          sitesProvider.overrideWithValue({
            'douyu': PlatformSite(douyu),
            'huya': PlatformSite(huya),
            'bilibili': PlatformSite(bilibili),
          }),
          enabledPlatformsProvider.overrideWithValue(['douyu', 'huya', 'bilibili']),
        ],
      );
      addTearDown(container.dispose);
    });

    test('next pages come only from platforms that have one; repeating pages stop after two', () async {
      final provider = combinedSearchProvider('英雄联盟');
      final keep = container.listen(provider, (_, _) {});
      addTearDown(keep.close);
      var state = await container.read(provider.future);
      expect(_ids(state.items), ['d1', 'd2', 'h1']);
      expect(state.failed, {'bilibili'}, reason: 'left out, the rest still shows');
      expect(state.cursors.keys, ['douyu']);

      final notifier = container.read(provider.notifier);
      await notifier.loadMore();
      state = container.read(provider).value!;
      expect(_ids(state.items), ['d1', 'd2', 'h1', 'd3']);
      expect(huya.cursors, [null], reason: 'huya had no second page');

      await notifier.loadMore();
      expect(container.read(provider).value!.hasMore, isTrue, reason: 'one repeating page is forgiven');
      await notifier.loadMore();
      state = container.read(provider).value!;
      expect(state.hasMore, isFalse, reason: 'a second repeating page ends the list');
      expect(_ids(state.items), ['d1', 'd2', 'h1', 'd3']);
    });

    test('a failed next page keeps its cursor for the retry', () async {
      final provider = combinedSearchProvider('lol');
      final keep = container.listen(provider, (_, _) {});
      addTearDown(keep.close);
      await container.read(provider.future);
      douyu.failFirst = true;
      await container.read(provider.notifier).loadMore();
      var state = container.read(provider).value!;
      expect(state.moreError, isA<NetworkFailure>());
      expect(state.cursors, {'douyu': const PageCursor('1')});

      await container.read(provider.notifier).loadMore();
      state = container.read(provider).value!;
      expect(state.moreError, isNull);
      expect(_ids(state.items), contains('d3'));
    });
  });

  testWidgets('F-SRC-01: wide windows filter by platform in a rail; the order menu applies', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    final douyu = FakeSite(
      'douyu',
      pages: [
        Page([_card('douyu', 'd1', online: 10), _card('douyu', 'd2', online: 90)]),
      ],
    );
    final huya = FakeSite(
      'huya',
      pages: [
        Page([_card('huya', 'h1', online: 50)]),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({'douyu': PlatformSite(douyu), 'huya': PlatformSite(huya)}),
          enabledPlatformsProvider.overrideWithValue(['douyu', 'huya']),
          recordingRoomsProvider.overrideWith((ref) => Stream.value(const {})),
        ],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.windows),
          home: const SearchPage(),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '英雄联盟');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
    await tester.pump();

    List<String> names() => [
      for (final card in tester.widgetList<RoomCardView>(find.byType(RoomCardView))) card.anchorName,
    ];
    expect(find.byType(TabBar), findsNothing, reason: 'the rail replaces the tabs');
    expect(find.widgetWithText(ListTile, '综合'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '斗鱼'), findsOneWidget);
    expect(names(), ['主播d1', '主播h1', '主播d2'], reason: 'smart: relevance in turn');

    await tester.tap(find.text('智能'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('按人数').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(names(), ['主播d2', '主播h1', '主播d1']);

    await tester.tap(find.widgetWithText(ListTile, '虎牙'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(names(), ['主播h1']);
    expect(huya.cursors, [null, null], reason: 'the platform list pages on its own');
  });
}
