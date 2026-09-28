import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/discover/discover_page.dart';
import 'package:pure_live_app/features/discover/followed_areas.dart';
import 'package:pure_live_app/features/rooms/card_marks.dart';

import 'fakes.dart';

void main() {
  Future<void> pumpDiscover(WidgetTester tester, Size size, {int rooms = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({
            for (final id in ['bilibili', 'douyu'])
              id: PlatformSite(
                FakeSite(
                  id,
                  pages: [
                    Page([for (var i = 0; i < rooms; i++) FakeSite(id).card('$id-$i')]),
                  ],
                ),
              ),
          }),
          recordingRoomsProvider.overrideWith((ref) => Stream.value(const {})),
          followedAreasProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          home: const DiscoverPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('推荐 and 分区 start at the page edge like the platform tabs above them', (tester) async {
    await pumpDiscover(tester, const Size(393, 852));
    final platformTab = tester.getTopLeft(find.text('哔哩哔哩'));
    final recommended = tester.getTopLeft(find.text('推荐'));
    expect(recommended.dx, lessThan(platformTab.dx + 24), reason: 'aligned to the start, not centred');
    expect(tester.getTopLeft(find.text('分区')).dx, greaterThan(recommended.dx));
  });

  testWidgets('principles §5.2: a landscape phone gets one top row that scrolls away', (tester) async {
    await pumpDiscover(tester, const Size(852, 393), rooms: 30);
    expect(find.text('发现'), findsNothing, reason: 'no page title at compact height');
    final platformRow = tester.getCenter(find.text('哔哩哔哩')).dy;
    expect(tester.getCenter(find.text('推荐')).dy, moreOrLessEquals(platformRow, epsilon: 2), reason: 'one row');
    expect(find.byType(SegmentedButton<DiscoverSection>), findsOneWidget);
    final header = tester.state<ScrollAwayHeaderState>(find.byType(ScrollAwayHeader));
    expect(header.shown, isTrue);

    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(header.shown, isFalse, reason: 'scrolling down hides the row');
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(header.shown, isTrue, reason: 'scrolling up brings it back');

    await tester.tap(find.text('分区'));
    await tester.pumpAndSettle();
    expect(find.byType(RoomCardView), findsNothing, reason: '分区 shows the areas instead');
  });
}
